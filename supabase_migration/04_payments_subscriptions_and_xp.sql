-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 04
-- File: 04_payments_subscriptions_and_xp.sql
-- Description: Paystack payments, subscription history, XP ledger, and ad reward sessions.
-- ==============================================================================

-- 1. Paystack Payments Log Table
CREATE TABLE IF NOT EXISTS public.payments (
    reference VARCHAR(100) PRIMARY KEY, -- Paystack transaction reference (PAY_...)
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    user_firebase_uid VARCHAR(64),
    user_email VARCHAR(255),
    phone_number VARCHAR(50),
    package_id VARCHAR(50) NOT NULL,
    package_name VARCHAR(100) NOT NULL,
    expected_amount_kes NUMERIC(10, 2) NOT NULL,
    expected_amount_subunits INT NOT NULL,
    currency VARCHAR(10) DEFAULT 'KES',
    duration_days INT,
    payment_method VARCHAR(50),
    paystack_transaction_id BIGINT,
    paystack_status VARCHAR(50),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed')),
    fulfilled BOOLEAN DEFAULT FALSE,
    fulfilled_at TIMESTAMPTZ,
    fulfillment_source VARCHAR(50),
    subscription_id VARCHAR(100),
    error_message TEXT,
    failure_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_user ON public.payments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_fulfilled ON public.payments(status, fulfilled);

CREATE OR REPLACE TRIGGER trg_payments_updated_at
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. User Subscription Validity & History Table
CREATE TABLE IF NOT EXISTS public.subscription_history (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    package_title VARCHAR(100),
    amount NUMERIC(10, 2),
    transaction_code VARCHAR(100),
    payment_channel VARCHAR(50),
    operator_receipt_number VARCHAR(100),
    paystack_reference VARCHAR(100),
    paystack_transaction_id BIGINT,
    purchase_date TIMESTAMPTZ DEFAULT NOW(),
    activation_date TIMESTAMPTZ DEFAULT NOW(),
    expiry_date TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    download_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscription_history_user ON public.subscription_history(user_id, expiry_date DESC);
CREATE INDEX IF NOT EXISTS idx_subscription_history_status ON public.subscription_history(status);

CREATE OR REPLACE TRIGGER trg_subscription_history_updated_at
BEFORE UPDATE ON public.subscription_history
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 3. Authoritative XP Balance Transactions Ledger Table
CREATE TABLE IF NOT EXISTS public.xp_transactions (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    type VARCHAR(50) NOT NULL CHECK (type IN ('ad_reward', 'donation', 'purchase', 'bonus', 'penalty', 'download_spend')),
    title VARCHAR(150),
    description TEXT,
    xp_amount INT NOT NULL,
    ad_unit_id VARCHAR(100),
    status VARCHAR(50) DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_xp_transactions_user ON public.xp_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_xp_transactions_type ON public.xp_transactions(type);

-- 4. Temporary Ad Reward Sessions Table (Prevents replay attacks & fraud)
CREATE TABLE IF NOT EXISTS public.ad_reward_sessions (
    id VARCHAR(100) PRIMARY KEY, -- Session UUID
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    reward_type VARCHAR(50) NOT NULL CHECK (reward_type IN ('video', 'interstitial')),
    ad_unit_id VARCHAR(100) NOT NULL,
    expected_xp INT NOT NULL,
    consumed BOOLEAN DEFAULT FALSE,
    consumed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ad_reward_sessions_lookup ON public.ad_reward_sessions(user_id, consumed, expires_at);

-- 5. Stored Procedure: Atomic Subscription Fulfillment
CREATE OR REPLACE FUNCTION public.fulfill_paystack_subscription(
    p_reference VARCHAR,
    p_paystack_tx_id BIGINT,
    p_channel VARCHAR
)
RETURNS JSONB AS $$
DECLARE
    v_payment RECORD;
    v_new_expiry TIMESTAMPTZ;
    v_current_expiry TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_payment FROM public.payments WHERE reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payment record not found');
    END IF;

    IF v_payment.fulfilled THEN
        RETURN jsonb_build_object('success', true, 'message', 'Already fulfilled');
    END IF;

    -- Fetch current user subscription expiry
    SELECT subscription_expiry INTO v_current_expiry FROM public.users WHERE id = v_payment.user_id;

    -- Calculate extended expiry date
    IF v_current_expiry IS NOT NULL AND v_current_expiry > NOW() THEN
        v_new_expiry := v_current_expiry + (v_payment.duration_days || ' days')::INTERVAL;
    ELSE
        v_new_expiry := NOW() + (v_payment.duration_days || ' days')::INTERVAL;
    END IF;

    -- 1. Update user profile
    UPDATE public.users SET
        is_subscribed = TRUE,
        subscription_plan = v_payment.package_id,
        subscription_expiry = v_new_expiry,
        updated_at = NOW()
    WHERE id = v_payment.user_id;

    -- 2. Insert subscription history record
    INSERT INTO public.subscription_history (
        id,
        user_id,
        user_firebase_uid,
        package_title,
        amount,
        transaction_code,
        payment_channel,
        paystack_reference,
        paystack_transaction_id,
        purchase_date,
        activation_date,
        expiry_date,
        status
    ) VALUES (
        gen_random_uuid()::TEXT,
        v_payment.user_id,
        v_payment.user_firebase_uid,
        v_payment.package_name,
        v_payment.expected_amount_kes,
        p_reference,
        p_channel,
        p_reference,
        p_paystack_tx_id,
        NOW(),
        NOW(),
        v_new_expiry,
        'active'
    );

    -- 3. Mark payment fulfilled
    UPDATE public.payments SET
        status = 'success',
        fulfilled = TRUE,
        fulfilled_at = NOW(),
        paystack_transaction_id = p_paystack_tx_id,
        paystack_status = 'success',
        updated_at = NOW()
    WHERE reference = p_reference;

    RETURN jsonb_build_object('success', true, 'expiry', v_new_expiry);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Deny client direct execution of payment fulfillment RPC
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) TO postgres, service_role;

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class Skeleton extends StatelessWidget {
  final double? height, width;
  final double borderRadius;

  const Skeleton({
    super.key,
    this.height,
    this.width,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Shimmer.fromColors(
      baseColor: isDark 
          ? Colors.white.withOpacity(0.05) 
          : Colors.black.withOpacity(0.05),
      highlightColor: isDark 
          ? Colors.white.withOpacity(0.1) 
          : Colors.black.withOpacity(0.1),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: isDark ? Colors.white : Colors.black12,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Skeleton(height: 40, width: 150),
                  const Skeleton(height: 40, width: 40, borderRadius: 20),
                ],
              ),
              const SizedBox(height: 30),
              const Skeleton(height: 50, width: double.infinity, borderRadius: 15),
              const SizedBox(height: 30),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(4, (index) => const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Skeleton(height: 35, width: 80, borderRadius: 20),
                  )),
                ),
              ),
              const SizedBox(height: 30),
              const Skeleton(height: 20, width: 100),
              const SizedBox(height: 20),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.7,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const Skeleton(borderRadius: 20),
              childCount: 4,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }
}

class LibrarySkeleton extends StatelessWidget {
  const LibrarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Skeleton(height: 40, width: 120),
                  const Skeleton(height: 40, width: 40, borderRadius: 20),
                ],
              ),
              const SizedBox(height: 30),
              const Skeleton(height: 45, width: double.infinity, borderRadius: 15),
              const SizedBox(height: 30),
              const Row(
                children: [
                  Skeleton(height: 40, width: 100, borderRadius: 12),
                  SizedBox(width: 10),
                  Skeleton(height: 40, width: 100, borderRadius: 12),
                ],
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const Skeleton(borderRadius: 20),
              childCount: 6,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 80),
          const Center(child: Skeleton(height: 100, width: 100, borderRadius: 50)),
          const SizedBox(height: 20),
          const Center(child: Skeleton(height: 25, width: 180)),
          const SizedBox(height: 10),
          const Center(child: Skeleton(height: 15, width: 120)),
          const SizedBox(height: 40),
          Column(
            children: List.generate(4, (index) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Skeleton(height: 60, width: double.infinity, borderRadius: 15),
            )),
          ),
        ],
      ),
    );
  }
}

class ExploreSkeleton extends StatelessWidget {
  const ExploreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 60),
              const Skeleton(height: 40, width: 120),
              const SizedBox(height: 40),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => const Skeleton(borderRadius: 15),
              childCount: 8,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }
}

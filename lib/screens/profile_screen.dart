import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF23144D), Color(0xFF090914)],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Center(
              child: Text(
                'My Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(height: 14),
            CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFF25C7FF),
              child: CircleAvatar(
                radius: 44,
                backgroundImage: NetworkImage(
                  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300',
                ),
              ),
            ),
            SizedBox(height: 14),
            Center(
              child: Text(
                'Cona Kipchoge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(
              child: Text(
                '@conakip',
                style: TextStyle(color: Color(0xFFCDCEEE), fontSize: 18),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Computer Science - University of Nairobi',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFD9DCF8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

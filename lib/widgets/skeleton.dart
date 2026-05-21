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
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.05),
      highlightColor: Colors.white.withOpacity(0.1),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: List.generate(4, (index) => const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Skeleton(height: 35, width: 80, borderRadius: 20),
            )),
          ),
          const SizedBox(height: 30),
          const Skeleton(height: 20, width: 100),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.7,
            ),
            itemCount: 4,
            itemBuilder: (context, index) => const Skeleton(borderRadius: 20),
          ),
        ],
      ),
    );
  }
}

class LibrarySkeleton extends StatelessWidget {
  const LibrarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 0.75,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => const Skeleton(borderRadius: 20),
          ),
        ],
      ),
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Skeleton(height: 40, width: 120),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
              ),
              itemCount: 8,
              itemBuilder: (context, index) => const Skeleton(borderRadius: 15),
            ),
          ),
        ],
      ),
    );
  }
}

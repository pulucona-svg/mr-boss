# Mirror Laikipia Project Instructions

## UI & Design Constraints

### Bottom Navigation Bar
- **Locked Style:** The bottom navigation bar must strictly use the following Material icons and labels. Do not change these unless explicitly requested by the user.
  - **Home:** `Icons.home_outlined` / `Icons.home_rounded` (Label: 'Home')
  - **Library:** `Icons.menu_book_outlined` / `Icons.menu_book_rounded` (Label: 'Library')
  - **Explore:** `Icons.explore_outlined` / `Icons.explore_rounded` (Label: 'Explore')
  - **Profile:** `Icons.person_outline` / `Icons.person_rounded` (Label: 'Profile')

### Dashboard (Home) Screen
- **Ad Removal:** The top ad carousel (previously located just below the notification bell) has been removed to reduce clutter. Do not re-add it.
- **Notification Bell:** Must remain in the top right corner of Dashboard, Library, and Explore screens.

### Navigation Logic
- **Back Button:** System back button must disengage active filters on Dashboard and Library screens before exiting or popping the screen. This is implemented using `PopScope`.

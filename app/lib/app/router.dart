import 'package:go_router/go_router.dart';

import '../domain/models.dart';

import '../presentation/screens/home_screen.dart';
import '../presentation/screens/journey_screen.dart';
import '../presentation/screens/mosque_details_screen.dart';
import '../presentation/screens/route_comparison_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/trip_planner_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'route',
          builder: (context, state) => const RouteComparisonScreen(),
          routes: [
            GoRoute(
              path: 'journey',
              builder: (context, state) => JourneyScreen(
                planIndex:
                    int.tryParse(state.uri.queryParameters['plan'] ?? '0') ?? 0,
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'trip',
          builder: (context, state) => const TripPlannerScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: 'mosque',
          builder: (context, state) => MosqueDetailsScreen(
            mosque: state.extra is MosqueCandidate ? state.extra as MosqueCandidate : null,
          ),
        ),
      ],
    ),
  ],
);

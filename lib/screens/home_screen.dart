// lib/screens/home_screen.dart
//
// Changes from previous version:
//   - Profile name and avatar index are loaded from Firestore via
//     ProfileService.profileStream() instead of being hardcoded.
//   - The header reacts in real-time to profile changes saved from
//     ProfileSettingsScreen.

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/profile_service.dart';
import 'profile_settings_screen.dart';
import 'settings_screen.dart';
import 'my_meds_screen.dart';
import 'add_medication.dart';

class PillBuddyHome extends StatefulWidget {
  const PillBuddyHome({super.key});

  @override
  _PillBuddyHomeState createState() => _PillBuddyHomeState();
}

class _PillBuddyHomeState extends State<PillBuddyHome> {
  int _selectedIndex = 0;
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  // Profile — updated from Firestore stream
  String _profileName = '';
  int _profileAvatarIndex = 0;

  final _profileService = ProfileService();

  static const List<Color> _avatarColors = [
    Color(0xFF3B71FE),
    Color(0xFF6B5BFF),
    Color(0xFF2BC8A7),
    Color(0xFFFFA726),
    Color(0xFFEF5350),
    Color(0xFF8E24AA),
    Color(0xFF42A5F5),
    Color(0xFF26A69A),
    Color(0xFFFFCA28),
  ];

  static const List<String> _avatarInitials = [
    'H', 'M', 'A', 'S', 'L', 'T', 'P', 'J', 'C',
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeContent(),
      MyMedsScreen(selectedDate: _selectedDay),
      const AddMedication(),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF3B71FE),
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage('assets/images/home.png'), size: 26),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/images/my_meds_icon.png'),
              size: 26,
            ),
            label: 'My Meds',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage('assets/images/add_meds.png'), size: 26),
            label: 'Add Meds',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/images/settings_icon.png'),
              size: 26,
            ),
            label: 'Setting',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return SafeArea(
      child: Column(
        children: [
          // ── Header — driven by Firestore profile stream ──────────────────
          StreamBuilder<Map<String, dynamic>?>(
            stream: _profileService.profileStream(),
            builder: (context, snapshot) {
              // Prefer live data; fall back to local state while loading
              final data = snapshot.data;
              final name = (data?['name'] as String?)?.isNotEmpty == true
                  ? data!['name'] as String
                  : _profileName.isNotEmpty
                      ? _profileName
                      : 'there';
              final avatarIdx =
                  (data?['avatarIndex'] as int?) ?? _profileAvatarIndex;

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const ProfileSettingsScreen(),
                          ),
                        );
                        // ProfileSettingsScreen now saves to Firestore, so
                        // the stream will update automatically. We also keep
                        // the local fallback in sync for the brief moment
                        // before the stream fires.
                        if (result is ProfileData) {
                          setState(() {
                            _profileName = result.name;
                            _profileAvatarIndex = result.avatarIndex;
                          });
                        }
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor:
                                _avatarColors[avatarIdx % _avatarColors.length],
                            child: Text(
                              _avatarInitials[avatarIdx %
                                  _avatarInitials.length],
                              style: const TextStyle(
                                fontSize: 22,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, $name',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[900],
                                ),
                              ),
                              const Text(
                                'Welcome!',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
              );
            },
          ),

          // ── Empty state ──────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/hp_capsule.png', height: 110),
                    const SizedBox(height: 20),
                    const Text(
                      'No Medications are\nScheduled for this day',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                      child: Text(
                        "If you haven't added a medication, please do so now.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ElevatedButton.icon(
                        onPressed: () => _onItemTapped(2), // jump to Add Meds
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          'Add Medication',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B71FE),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Calendar ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.only(bottom: 5),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: TableCalendar(
              rowHeight: 40,
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: EdgeInsets.symmetric(vertical: 8),
                titleTextStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              calendarStyle: const CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: Color(0xFF3B71FE),
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                todayDecoration: BoxDecoration(
                  color: Color(0xFFE3F2FD),
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                defaultTextStyle: TextStyle(fontSize: 13),
                weekendTextStyle: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
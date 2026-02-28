import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaterialApp(home: HomeScreen(), debugShowCheckedModeBanner: false));

// --- 1. DATA MODELS --- [cite: 341-342, 585]
class WeatherInfo {
  final String cityName;
  final double temp;
  final double wind;
  final int humidity;
  final List<DailyForecast> daily;

  WeatherInfo({required this.cityName, required this.temp, required this.wind, required this.humidity, required this.daily});

  factory WeatherInfo.fromJson(String name, Map<String, dynamic> json) {
    return WeatherInfo(
      cityName: name,
      temp: json['current_weather']['temperature'],
      wind: json['current_weather']['windspeed'],
      humidity: json['hourly']['relativehumidity_2m'][0],
      daily: List.generate(3, (i) => DailyForecast(
        date: json['daily']['time'][i],
        maxTemp: json['daily']['temperature_2m_max'][i],
      )),
    );
  }
}

class DailyForecast {
  final String date;
  final double maxTemp;
  DailyForecast({required this.date, required this.maxTemp});
}

// --- 2. HOME SCREEN (Search & Recent) --- [cite: 566-568, 581-583]
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  List<String> _history = [];

  @override
  void initState() { super.initState(); _loadHistory(); }

  _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList('history') ?? []); //
  }

  _saveCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_history.contains(city)) {
      _history.insert(0, city);
      await prefs.setStringList('history', _history);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Weather Search")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: "Enter City (e.g. Lahore)",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () {
                  if (_controller.text.isNotEmpty) {
                    _saveCity(_controller.text);
                    Navigator.push(context, MaterialPageRoute(builder: (c) => DetailsScreen(city: _controller.text)));
                  }
                }),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Recent Searches", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(_history[i]),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => DetailsScreen(city: _history[i]))),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- 3. DETAILS SCREEN (API & Display) --- [cite: 569-575]
class DetailsScreen extends StatelessWidget {
  final String city;
  const DetailsScreen({super.key, required this.city});

  Future<WeatherInfo> getWeather() async {
    // Step A: Geocoding (City Name -> Coordinates) [cite: 318, 577]
    final geoUrl = 'https://geocoding-api.open-meteo.com/v1/search?name=$city&count=1';
    final geoRes = await http.get(Uri.parse(geoUrl));
    final geoData = jsonDecode(geoRes.body);

    if (geoData['results'] == null) throw Exception("City Not Found");

    final lat = geoData['results'][0]['latitude'];
    final lon = geoData['results'][0]['longitude'];

    // Step B: Fetch Weather using Coordinates [cite: 572, 578]
    final weatherUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&hourly=relativehumidity_2m&daily=temperature_2m_max&timezone=auto';
    final res = await http.get(Uri.parse(weatherUrl));

    if (res.statusCode == 200) {
      return WeatherInfo.fromJson(city, jsonDecode(res.body));
    } else {
      throw Exception("Failed to fetch weather");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(city)),
      body: FutureBuilder<WeatherInfo>(
        future: getWeather(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator()); //
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}")); //

          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Current Weather Card [cite: 573]
                Card(
                  color: Colors.blueAccent,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Text(data.cityName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24)),
                        Text("${data.temp}°C", style: const TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.bold)),
                        const Divider(color: Colors.white),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text("Wind: ${data.wind} km/h", style: const TextStyle(color: Colors.white)),
                            Text("Humidity: ${data.humidity}%", style: const TextStyle(color: Colors.white)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("3-Day Forecast", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                // Forecast List [cite: 573, 579]
                Expanded(
                  child: ListView.builder(
                    itemCount: data.daily.length,
                    itemBuilder: (c, i) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.calendar_month),
                        title: Text(data.daily[i].date),
                        trailing: Text("${data.daily[i].maxTemp}°C", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
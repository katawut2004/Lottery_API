import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(GetMaterialApp(
      title: 'ตรวจหวยไทย',
      theme: ThemeData(primarySwatch: Colors.green),
      home: LottoHomePage(),
    ));

class LottoController extends GetxController {
  var lottoData = {}.obs;
  var loading = false.obs;
  var error = ''.obs;
  var history = <Map<String, String>>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchLatest();
  }

  Future<void> fetchLatest() async {
    await fetchLottoData('https://lotto.api.rayriffy.com/latest');
  }

  Future<void> fetchLottoData(String url) async {
    loading.value = true; //เท่
    error.value = '';
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        if (json['status'] == 'success') {
          lottoData.value = json['response'];
        } else {
          error.value = 'API returned status not success';
        }
      } else {
        error.value = 'HTTP error: ${resp.statusCode}';
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<String> checkPrizeAll(String number) async {
    // ไล่ตรวจย้อนหลังไปจนเจอ
    DateTime checkDate = DateTime.now();
    for (int i = 0; i < 24; i++) {
      String dateParam = adjustToLottoDate(checkDate);
      await fetchLottoData('https://lotto.api.rayriffy.com/lotto/$dateParam');

      String result = checkPrize(number);
      if (!result.contains('ไม่ถูกรางวัล')) {
        return result;
      }

      // ย้อนกลับไปงวดก่อนหน้า
      if (checkDate.day >= 16) {
        checkDate = DateTime(checkDate.year, checkDate.month, 1);
      } else {
        checkDate = DateTime(checkDate.year, checkDate.month - 1, 16);
      }
    }
    return 'ไม่ถูกรางวัลใน 12 เดือนล่าสุด';
  }

  String adjustToLottoDate(DateTime picked) {
    if (picked.day >= 16) {
      return "${picked.year}-${picked.month.toString().padLeft(2, '0')}-16";
    } else {
      return "${picked.year}-${picked.month.toString().padLeft(2, '0')}-01";
    }
  }

  String checkPrize(String number) {
    if (lottoData.isEmpty) return '';
    String message = 'ไม่ถูกรางวัล';

    for (var prize in lottoData['prizes']) {
      List nums = prize['number'] as List;
      if (nums.contains(number)) {
        message =
            '🎉 ถูกรางวัล: ${prize['name']} (${prize['reward']} บาท) งวดวันที่: ${lottoData['date']}';
        break;
      }
    }
    for (var prize in lottoData['runningNumbers']) {
      List nums = prize['number'] as List;
      if (nums.contains(number)) {
        message =
            '🎉 ถูกรางวัล: ${prize['name']} (${prize['reward']} บาท) งวดวันที่: ${lottoData['date']}';
        break;
      }
    }

    history.add({
      'date': lottoData['date'],
      'number': number,
      'result': message,
    });

    return message;
  }
}

class LottoHomePage extends StatefulWidget {
  @override
  State<LottoHomePage> createState() => _LottoHomePageState();
}

class _LottoHomePageState extends State<LottoHomePage> {
  final LottoController lottoCtrl = Get.put(LottoController());
  final TextEditingController numberCtrl = TextEditingController();
  String resultMessage = '';
  String? scannedNumber;
  bool scanning = false;

  final MobileScannerController scannerController = MobileScannerController();

  void startScan() {
    scannerController.start();
    setState(() => scanning = true);
  }

  void stopScan() {
    scannerController.stop();
    setState(() => scanning = false);
  }

  Widget buildScanner() {
    return MobileScanner(
      controller: scannerController,
      onDetect: (capture) {
        final List<Barcode> barcodes = capture.barcodes;
        for (final barcode in barcodes) {
          final String? rawValue = barcode.rawValue;
          if (rawValue != null) {
            String digits = rawValue.replaceAll(RegExp(r'\D'), '');
            if (digits.length >= 6) {
              scannedNumber = digits.substring(0, 6);
              lottoCtrl.checkPrizeAll(scannedNumber!).then((result) {
                setState(() => resultMessage = result);
              });
              stopScan();
              break;
            }
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (lottoCtrl.loading.value && lottoCtrl.lottoData.isEmpty) {
        return Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (lottoCtrl.error.value.isNotEmpty) {
        return Scaffold(body: Center(child: Text('Error: ${lottoCtrl.error}')));
      }

      return Scaffold(
        appBar: AppBar(
          title: Text('ตรวจหวยไทย'),
          actions: [
            IconButton(
              icon: Icon(Icons.history),
              onPressed: () => Get.to(() => HistoryPage()),
            )
          ],
        ),
        body: scanning
            ? buildScanner()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: numberCtrl,
                      decoration: InputDecoration(
                        labelText: 'กรอกเลขสลาก (6 หลัก)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (numberCtrl.text.trim().isNotEmpty) {
                          lottoCtrl
                              .checkPrizeAll(numberCtrl.text.trim())
                              .then((result) {
                            setState(() => resultMessage = result);
                          });
                        }
                      },
                      child: Text('ตรวจรางวัลอัตโนมัติ'),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: startScan,
                      icon: Icon(Icons.qr_code_scanner),
                      label: Text('สแกน QR สลาก'),
                    ),
                    SizedBox(height: 16),
                    Text(
                      resultMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

class HistoryPage extends StatelessWidget {
  final LottoController lottoCtrl = Get.find<LottoController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ประวัติการตรวจหวย')),
      body: Obx(() {
        if (lottoCtrl.history.isEmpty) {
          return Center(child: Text('ยังไม่มีประวัติการตรวจ'));
        }
        return ListView.builder(
          itemCount: lottoCtrl.history.length,
          itemBuilder: (context, index) {
            final item = lottoCtrl.history[index];
            return ListTile(
              title: Text('${item['number']} - ${item['result']}'),
              subtitle: Text('งวดวันที่: ${item['date']}'),
            );
          },
        );
      }),
    );
  }
}

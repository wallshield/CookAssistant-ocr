import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cook_assistant/widgets/button/primary_button.dart';
import 'package:cook_assistant/widgets/button/secondary_button.dart';
import 'package:cook_assistant/ui/theme/color.dart';
import 'package:cook_assistant/ui/theme/text_styles.dart';
import 'package:cook_assistant/widgets/text_field.dart';
import 'package:cook_assistant/widgets/popup.dart';

class AddIngredientsPage extends StatefulWidget {
  @override
  _AddIngredientsPageState createState() => _AddIngredientsPageState();
}

class _AddIngredientsPageState extends State<AddIngredientsPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _expirationDateController = TextEditingController();

  Future<void> pickAndAnalyzeImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      print("선택된 이미지가 없습니다.");
      return;
    }
    print("선택된 이미지: ${image.path}");
    String? extractedText = await annotateImage(image.path);
    if (extractedText == null) {
      print("추출된 텍스트가 없습니다.");
      return;
    }
    print("추출된 텍스트: $extractedText");
    Map<String, String> parsedData = await queryOpenAI(extractedText);
    setState(() {
      _nameController.text = parsedData['name'] ?? '알 수 없음';
      _quantityController.text = parsedData['amount'] ?? '알 수 없음';
      _expirationDateController.text = parsedData['expiration'] ?? '알 수 없음';
    });
  }

  Future<String?> annotateImage(String imagePath) async {
    try {
      String base64Image = await encodeImageToBase64(imagePath);
      Uri uri = Uri.parse('https://vision.googleapis.com/v1/images:annotate');
      String apiKey = dotenv.get('GOOGLE_CLOUD_VISION_API_KEY');
      String projectId = dotenv.get('GOOGLE_CLOUD_PROJECT_ID');
      var response = await http.post(
        uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $apiKey',
          HttpHeaders.contentTypeHeader: 'application/json',
          'x-goog-user-project': projectId,
        },
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': base64Image},
              'features': [{'type': 'TEXT_DETECTION'}]
            }
          ]
        }),
      );
      if (response.statusCode != 200) throw "Vision API 호출 실패: ${response.statusCode}";
      var jsonResponse = json.decode(response.body);
      if (jsonResponse['responses'][0]['textAnnotations'].isEmpty) throw "어노테이션을 찾을 수 없습니다.";
      return jsonResponse['responses'][0]['textAnnotations'][0]['description'];
    } catch (e) {
      print("annotateImage 오류: $e");
      return null;
    }
  }

  Future<Map<String, String>> queryOpenAI(String text) async {
    try {
      Uri uri = Uri.parse(dotenv.get('OPENAI_API_URL'));
      String apiKey = dotenv.get('OPENAI_API_KEY');
      var response = await http.post(
        uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $apiKey',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'system', 'content': '제품명과 수량 그리고 소비기한을 순서대로 나열하라. ex) 과자,2,2024-02-03  만약 소비기한이 없다면 x로 표시하라. ex) 과자,2,x  만약 두가지 이상의 종류가 나온다면 처음에 나온 한가지 종류만 출력하라. ex) 과자,2,x 와 우유,3,x 가 나온다면 과자,2,x 만 출력하라'},
            {'role': 'user', 'content': text},
          ],
        }),
      );
      if (response.statusCode != 200) throw "OpenAI API 호출 실패: ${response.statusCode}";
      var jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      var content = jsonResponse['choices'][0]['message']['content'];
      print("OpenAI 응답: $content");
      return parseAIResponse(content);
    } catch (e) {
      print("queryOpenAI 오류: $e");
      return {'name': '오류', 'amount': '오류', 'expiration': '오류'};
    }
  }

  Map<String, String> parseAIResponse(String response) {
    try {
      RegExp exp = RegExp(r"([^,]+),([^,]+),([^,]+)");
      var matches = exp.firstMatch(response);
      if (matches != null) {
        return {
          'name': matches.group(1) ?? '알 수 없음',
          'amount': matches.group(2) ?? '지정되지 않음',
          'expiration': matches.group(3) ?? '제공되지 않음',
        };
      } else {
        print("응답에서 항목을 찾을 수 없습니다.");
        return {'name': '알 수 없음', 'amount': '알 수 없음', 'expiration': '알 수 없음'};
      }
    } catch (e) {
      print("parseAIResponse 오류: $e");
      return {'name': '오류', 'amount': '오류', 'expiration': '오류'};
    }
  }

  Future<String> encodeImageToBase64(String imagePath) async {
    try {
      File imageFile = File(imagePath);
      List<int> imageBytes = await imageFile.readAsBytes();
      return base64Encode(imageBytes);
    } catch (e) {
      print("이미지 인코딩 오류: $e");
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '식재료 추가하기',
          style: AppTextStyles.headingH4.copyWith(
              color: AppColors.neutralDarkDarkest),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          children: [
            Text(
              '식재료 추가 AI 도우미',
              textAlign: TextAlign.center,
              style: AppTextStyles.headingH3.copyWith(
                  color: AppColors.neutralDarkDarkest),
            ),
            const SizedBox(height: 8.0),
            Text(
              '음성 인식나 이미지 인식을 통해 손쉽게 재료를 등록해 보세요!',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.neutralDarkLight),
            ),
            const SizedBox(height: 48.0),
            PrimaryButton(
              text: '음성으로 등록하기',
              onPressed: () => showRegistrationPopup(context, 'voice'),
            ),
            SecondaryButton(
              text: '이미지로 등록하기',
              onPressed: pickAndAnalyzeImage,
            ),
            const SizedBox(height: 60.0),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '식재료 이름',
                    style: AppTextStyles.headingH5.copyWith(
                        color: AppColors.neutralDarkDark),
                  ),
                ],
              ),
            ),
            CustomTextField(
              controller: _nameController,
              label: '식재료 이름',
              hint: 'ex) 돼지고기',
            ),
            const SizedBox(height: 16.0),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '식재료 양',
                    style: AppTextStyles.headingH5.copyWith(
                        color: AppColors.neutralDarkDark),
                  ),
                ],
              ),
            ),
            CustomTextField(
              controller: _quantityController,
              label: '식재료 양',
              hint: '단위를 포함해서 입력하세요  ex) 400g',
            ),
            const SizedBox(height: 16.0),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '소비기한',
                    style: AppTextStyles.headingH5.copyWith(
                        color: AppColors.neutralDarkDark),
                  ),
                ],
              ),
            ),
            CustomTextField(
              controller: _expirationDateController,
              label: '소비기한',
              hint: '0000년 00월 00일',
            ),
            const Spacer(),
            PrimaryButton(
              text: '완료하기',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('등록 완료'),
                      content: Text('등록되었습니다.'),
                      actions: <Widget>[
                        TextButton(
                          child: Text('확인'),
                          onPressed: () {
                            Navigator.of(context).pop(); // 알림 창을 닫습니다.
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

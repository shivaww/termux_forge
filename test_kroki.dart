import 'dart:convert';
import 'dart:io';

void main() async {
  final code = 'graph TD\nA-->B';
  final bytes = utf8.encode(code);
  final compressed = zlib.encode(bytes);
  final base64Code = base64UrlEncode(compressed);
  final url = 'https://kroki.io/mermaid/png/' + base64Code;
  print(url);
  
  final request = await HttpClient().getUrl(Uri.parse(url));
  final response = await request.close();
  print('Status: ${response.statusCode}');
}

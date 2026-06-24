import 'dart:io';

void main() async {
  final body = File('ddg_test.html').readAsStringSync();
  final blockRegex = RegExp(r'<div class="result results_links[^>]*>([\s\S]*?)<div class="clear"></div>');
  final titleRegex = RegExp(r'<h2 class="result__title">\s*<a[^>]*>([\s\S]*?)</a>');
  final urlRegex = RegExp(r'href="//duckduckgo.com/l/\?uddg=([^"&]+)');
  final snippetRegex = RegExp(r'<a class="result__snippet"[^>]*>([\s\S]*?)</a>');
  
  print('Blocks: ${blockRegex.allMatches(body).length}');
  for (final match in blockRegex.allMatches(body)) {
    final block = match.group(1) ?? '';
    final titleMatch = titleRegex.firstMatch(block);
    final urlMatch = urlRegex.firstMatch(block);
    final snippetMatch = snippetRegex.firstMatch(block);
    print('Title: ${titleMatch != null}, URL: ${urlMatch != null}, Snippet: ${snippetMatch != null}');
    if (titleMatch != null && urlMatch != null && snippetMatch != null) {
      print('FOUND ONE!');
    }
  }
}

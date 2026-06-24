void main() {
  var s = r"\[ x^2 \]";
  var r1 = s.replaceAllMapped(RegExp(r'\\\[([\s\S]*?)\\\]'), (m) => '\$\$' + (m.group(1) ?? '') + '\$\$');
  print(r1);
}

import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

# 1. Remove _startResearchLoop and _runResearchLoop entirely
# Find the start of _startResearchLoop
match_start = re.search(r'^\s*void _startResearchLoop', content, re.MULTILINE)
if match_start:
    start_idx = match_start.start()
    # Find the end of _runResearchLoop which is right before the Widget build(BuildContext context) of _ChatHomePageState
    match_end = re.search(r'^\s*@override\s*Widget build\(BuildContext context\)', content[start_idx:], re.MULTILINE)
    if match_end:
        end_idx = start_idx + match_end.start()
        # Find where _activeSession getter is to avoid deleting it
        match_active = re.search(r'^\s*ChatSession get _activeSession', content[start_idx:], re.MULTILINE)
        if match_active:
            end_idx = start_idx + match_active.start()
        content = content[:start_idx] + content[end_idx:]

# 2. Remove deepResearchEnabled parameter and fields
content = re.sub(r'\s*bool _deepResearchEnabled = false;\n?', '\n', content)
content = re.sub(r'\s*final deepResearchRaw = prefs\.getBool\(\'deep_research_enabled_v1\'\);\n?', '\n', content)
content = re.sub(r'\s*_deepResearchEnabled = deepResearchRaw \?\? false;\n?', '\n', content)
content = re.sub(r'\s*await prefs\.setBool\(\'deep_research_enabled_v1\', _deepResearchEnabled\);\n?', '\n', content)
content = re.sub(r'\s*if \(_deepResearchEnabled && !_agenticEnabled\) \{.*?\n\s*\}\n?', '', content, flags=re.DOTALL)
content = re.sub(r'\s*if \(_deepResearchEnabled\) \{.*?\n\s*\}\n?', '', content, flags=re.DOTALL)
content = re.sub(r'\s*deepResearchEnabled: _deepResearchEnabled,\n?', '', content)
content = re.sub(r'\s*onDeepResearchEnabledChanged: \(val\) async \{.*?\n\s*\},\n?', '', content, flags=re.DOTALL)
content = re.sub(r'\s*required this\.deepResearchEnabled,\n?', '', content)
content = re.sub(r'\s*required this\.onDeepResearchEnabledChanged,\n?', '', content)
content = re.sub(r'\s*final bool deepResearchEnabled;\n?', '', content)
content = re.sub(r'\s*final ValueChanged<bool> onDeepResearchEnabledChanged;\n?', '', content)

# Remove from ChatSessionWidget arguments
content = re.sub(r'\s*deepResearchEnabled: deepResearchEnabled,\n?', '', content)

# Remove the UI switches for Deep Research
deep_research_ui = r'''\s*SwitchListTile\(
\s*title: const Text\('Deep Research'\),
\s*subtitle: const Text\('Autonomous multi-step deep web research'\),
\s*value: _deepResearchEnabled,
\s*activeColor: const Color\(0xFF7B4E2E\),
\s*onChanged: \(val\) \{
\s*setState\(\(\) => _deepResearchEnabled = val\);
\s*widget\.onDeepResearchEnabledChanged\(val\);
\s*\},
\s*\),'''
content = re.sub(deep_research_ui, '', content)

# Fix hintText logic
content = re.sub(r"hintText: deepResearchEnabled \? 'Deep Research Mode is ON\.\.\.' : 'Message any provider\.\.\.',", "hintText: 'Message any provider...',", content)

# Remove onStartResearch from InputArea and ChatSessionWidget
content = re.sub(r'\s*final VoidCallback\? onStartResearch;\n?', '', content)
content = re.sub(r'\s*this\.onStartResearch,\n?', '', content)
content = re.sub(r'\s*onStartResearch: _startResearchLoop,\n?', '', content)

# Fix comma issues and dangling commas if any (optional, Dart formatter handles it, but let's be careful)

with open('lib/main.dart', 'w') as f:
    f.write(content)
print("Done")

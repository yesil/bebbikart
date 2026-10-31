extends RefCounted
## Big-screen strings in the game manager's language (contracts §2b). One table per language
## in res://data/strings.json, with the same keys in each (bun test checks). The language is
## config.language: picked in the options menu, saved in user://settings.cfg, sent to the server
## so every phone follows it. No fallback: a missing key or language is push_error'd and shows
## up on screen as "⚠ lang:key", never as quiet English.
##   const I18n = preload("res://ui/i18n.gd")
##   I18n.t("menu.title")            I18n.f("menu.loading", [name])

const DATA_PATH := "res://data/strings.json"
const MISSING := "⚠ %s:%s"

static var language := ""
static var _tables := {}
static var _load_error := ""


## Loads the tables once. Returns "" or why they can't be used (missing file, bad JSON, a
## language without a table, keys that differ between languages).
static func load_tables() -> String:
	if not _tables.is_empty() or _load_error != "":
		return _load_error
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text == "":
		_load_error = "%s is missing or empty (%s)" % [DATA_PATH, error_string(FileAccess.get_open_error())]
		return _load_error
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_load_error = "%s is not a JSON object" % DATA_PATH
		return _load_error
	var problems: PackedStringArray = []
	for lang in Protocol.LANGUAGES:
		if typeof(data.get(lang)) != TYPE_DICTIONARY:
			problems.append("no \"%s\" table" % lang)
	if problems.is_empty():
		var first: Dictionary = data[Protocol.LANGUAGES[0]]
		for lang in Protocol.LANGUAGES:
			var table: Dictionary = data[lang]
			for k in first:
				if not table.has(k):
					problems.append("\"%s\" has no %s" % [lang, k])
			for k in table:
				if not first.has(k):
					problems.append("\"%s\" has %s, \"%s\" does not" % [lang, k, Protocol.LANGUAGES[0]])
	if not problems.is_empty():
		_load_error = "%s: %s" % [DATA_PATH, "; ".join(problems)]
		return _load_error
	for lang in Protocol.LANGUAGES:
		_tables[lang] = data[lang]
	return ""


## Switches every later t()/f() to `lang`. Returns "" or why not (unknown language, bad tables).
static func set_language(lang: String) -> String:
	var err := load_tables()
	if err != "":
		push_error("i18n: " + err)
		return err
	if not Protocol.LANGUAGES.has(lang):
		err = "unknown language \"%s\" (known: %s)" % [lang, ", ".join(Protocol.LANGUAGES)]
		push_error("i18n: " + err)
		return err
	language = lang
	return ""


## The text for `key` in the current language.
static func t(key: String) -> String:
	var table: Dictionary = _tables.get(language, {})
	if not table.has(key):
		push_error("i18n: no \"%s\" text for %s" % [language, key])
		return MISSING % [language, key]
	return String(table[key])


## t(key) formatted with `args` (GDScript % placeholders).
static func f(key: String, args: Array) -> String:
	var template := t(key)
	if template.begins_with("⚠"):
		return "%s %s" % [template, str(args)]
	return template % args

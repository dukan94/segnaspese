# ML Kit registra opzionalmente riconoscitori testo per altri alfabeti
# (cinese/giapponese/coreano/devanagari): l'app usa solo il riconoscitore
# latino (v. lib/presentation/receipt/receipt_scan_page.dart), quelle classi
# non sono mai referenziate a runtime ma R8 le vede citate nei metadati del
# plugin e fallisce in fase di build in release senza queste regole.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

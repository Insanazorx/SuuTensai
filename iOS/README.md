# Rigor — iPhone editörü

iOS 17 ve üzeri için küçük, yerel SwiftUI uygulaması. `RigorCore` Swift paketini
kullanır; checker uygulamanın içinde çalışır, sunucu veya internet gerekmez.

## Açma ve çalıştırma

1. `iOS/Rigor.xcodeproj` dosyasını Xcode ile aç.
2. **Rigor** şemasını ve bir iPhone simülatörünü seç, Run'a bas.
3. Gerçek iPhone için **Signing & Capabilities → Team** alanından kendi Apple
   geliştirme takımını seç; gerekiyorsa bundle identifier'ı benzersiz yap.
   Telefonu hedef olarak seçip Run'a bas.

Proje kökündeki paket yerel bağımlılıktır; proje klasörünü taşırken kökü de taşı.
Paket Swift 6.4 veya üzerini gerektirir. İmzalama takımı projeye gömülmemiştir.

## Kullanım

- Metni yazmayı bıraktıktan 450 ms sonra parser ve kernel kontrolü başlar.
  Menüdeki **Şimdi kontrol et** beklemeden kontrol başlatır.
- Kontrol ana UI aktörünün dışında, sırayla çalışır. Yeni düzenleme eski görevi
  iptal eder; kernel iptali düzenli olarak yoklar. Eski sonuç yeni taslağa uygulanmaz.
- İlk hata, aşamasıyla birlikte checker API'sinden döner. Editör mesajı ve
  satır/sütunu gösterir; konum düğmesi ilgili metni seçer. Unicode UTF-8
  konumları UITextView'ın UTF-16 seçimine dönüştürülür.
- Anahtar kelimeler, Type/Prop, bildirim isimleri, yorumlar, string'ler, sayılar,
  operatörler ve delikler renklendirilir. Eksik kod da renklendirilir; bunun
  doğruluğunu ayrı linter belirler. Hata alt çizgisi renklerin üzerinde korunur.
- Başarılı kontrolde bildirim sayısı ve aksiyom bağımlılıkları görünür.
  Ayrıntılar düğmesi isimleri açar. Boş kaynak ayrı bir durumdur.
- Taslak değişiklikten 250 ms sonra atomik olarak Application Support altında
  `Rigor/Taslak.rigor` dosyasına kaydedilir. Uygulama pasifleşirken de kaydedilir;
  yeniden açılışta geri yüklenir. Kayıt hatası ekranda görünür.
- Klavyenin üstündeki yatay kaydırılabilir şeritte yalnızca
  `{`, `}`, `(`, `)`, `->`, `=>`, `<`, `>`, `:` bulunur. Birine dokunmak
  imlecin olduğu yere tam o sembolü ekler.
- Telefon yatay çevrildiğinde checker sonucu sağda, editör solda görünür;
  klavye açıkken de editör için alan kalır.
- Menüden üç örnek açılabilir veya taslak Dosyalar'a dışa aktarılabilir.

Bu sürüm tek taslak düzenler. Girdi Rigor bildirimlerinden oluşur (`theorem`,
`def`, `inductive` vb.); bağımsız çıplak ifadeler için REPL modu yoktur.
`Fundamentals.rigor` uygulamaya dahildir ve açık `import` ile kullanılabilir.
Diğer import'lar hata verir; cihaz dosya sistemi keyfî olarak taranmaz.
İlk hata gösterilir; çoklu hata kurtarma mevcut parser'da bulunmaz.
Editör API'si dosya başına 256 KB, bütün yükleme için 1 MB sınırı uygular.
Mevcut CLI dosya yükleme davranışı korunur.
VS Code tarafında da aynı checker'a bağlı linter ve sözdizimi renklendirmesi
vardır: [VS Code eklentisi](../VSCode/rigor/README.md).

## Betikle build ve kurulum

```sh
./install.sh ios                              # simülatör build'i
./install.sh ios --simulator --run            # çalışan simülatöre yükle ve aç
./install.sh ios --device auto --run          # bağlı iPhone'a imzala, kur, aç
```

Ayrıntılar: [Üç kurulum hedefi](../Docs/Install.md).

## Doğrulama

Proje kökünde:

```sh
bash Scripts/test.sh
bash Scripts/test-ios.sh SIMULATOR_UDID
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/test-editor.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project iOS/Rigor.xcodeproj -scheme Rigor \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/iOS CODE_SIGNING_ALLOWED=NO build
```

`test-editor.sh`, UI'nın kullandığı `EditorModel.swift` dosyasını macOS üzerinde
çalıştırır; hızlı düzenlemede son sonucun korunmasını, hata konumunu, taslak
kaydını, geri yüklemeyi ve yerleşik örnekleri doğrular. iPhone klavye ve dokunma
davranışının otomatik UI testi değildir.

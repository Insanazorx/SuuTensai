# Rigor Language — VS Code

`.rigor` dosyaları için sözdizimi renklendirmesi ve gerçek Rigor checker'ına
bağlı canlı hata işaretleme. Haricî npm çalışma zamanı bağımlılığı yoktur.

## Kurulum

Proje kökünde:

```sh
bash Scripts/build.sh debug
python3 Scripts/package-vscode.py
code --install-extension .build/rigor-language-0.3.0.vsix --force
```

`code` PATH'te değilse VS Code'da **Extensions → … → Install from VSIX…**
ile üretilen paketi seç. Gerekirse **Developer: Reload Window** çalıştır.
Proje kök klasörünü aç; `.rigor` dosyasının dil modu **Rigor** olacaktır.
Bu yerel eklenti Marketplace'e yayımlanmış değildir.

## Özellikler

- Swift'e benzer tema scope'larıyla anahtar kelimeler, türler, parametreler,
  bildirimler ve `F()`, `f<A>(x)` gibi çağrıların isimleri renklendirilir.
  Yorumlar, string'ler, sayılar ve delikler ayrı görünür. `->` ve `=>` tek
  operatör token'ıdır; iki karakteri de aynı renktir. Generic ayraçları otomatik
  kapanır; okların sonundaki `>` parantez renklendirmesine girmez.
- Parantez eşleme, otomatik kapatma, yorum kısayolları, girinti ve temel
  `theorem`, `def`, `inductive`, `fundamentals` snippet'leri bulunur.
- Çalışma klasörü başına kalıcı `SuuTensai --lsp` sunucusu çalışır. Her
  düzenleme, varsayılan olarak ek bekleme olmadan sunucuya iletilir; kaydetmek
  veya komut çalıştırmak gerekmez. Pahalı kontroller sunucunun mesaj döngüsü
  dışında, iptal edilebilir görevlerde çalışır.
  Sorunlar kırmızı alt çizgi, hover ve **Problems** panelinde görünür.
- Açık `.rigor` dosyalarındaki kaydedilmemiş metinler checker'a gönderilir.
  Aynı çalışma klasöründeki açık import dosyalarının taslakları da hesaba katılır.
  Diğer import'lar diskten, import eden dosyaya göre çözülür.
- UTF-8 kaynak konumları VS Code'un sıfır tabanlı UTF-16 konumlarına çevrilir.
  Import hataları ilgili dosyada gösterilir ve yinelenen kayıtlar birleştirilir.
- Yeni düzenleme eski kontrolü iptal eder. Belge sürümü ve çalışma revizyonu
  birlikte izlenir; import değiştiğinde önceki kontrolden kalan sonuçlar da
  gösterilmez. Kapanan/düzeltilen dosyaların eski hataları kaldırılır.
- Sunucu, her kontrolde yeniden başlatılmaz; çalışma klasörü kapanıncaya veya
  sunucu yeniden başlatılıncaya kadar açık kalır. Beklenmeyen kapanmada sınırlı
  sayıda yeniden bağlanma denenir. İsteklerin zaman aşımı 15 saniyedir.
- Durum çubuğu kontrol durumunu; başarılı kontroldeki tooltip aksiyom
  bağımlılıklarını gösterir.
- Bir `.rigor` dosyası açıldığında sağdaki ayrı editör grubunda **Rigor — Canlı
  Kontrol** görünür. Yazarken sonuç güncellenir; imleç ve klavye odağı kaynakta
  kalır. Panel güncel kontrol durumunu, hata konumunu, doğrulanan bildirimleri,
  aksiyom bağımlılıklarını ve kontrol süresini gösterir. Hata konumuna tıklamak
  ilgili kaynak satırını açar. Paneli kapatmak aynı oturumda otomatik açılmayı
  durdurur; **Rigor: Show Check Details** komutuyla yeniden açılır.

Linter, sözdizimi ve tür/ispat doğruluğunu kontrol eder. Mevcut parser gibi
dosya başına ilk hatada durur; hata düzeltildiğinde sonraki kontrol yapılır.
Bu sürüm her güncellemede tam belgeyi ve import'larını kontrol eder.
Checker yalnızca güvenilen yerel çalışma klasörlerinde çalışır. Çalıştırmadan
renklendirme kullanılabilir.

## Komutlar ve ayarlar

- **Rigor: Check Current File**: beklemeden kontrol.
- **Rigor: Build Checker**: Swift checker'ını yeniden derle; çekirdek kodunu
  değiştirdiğinde bu komutu kullan.
- **Rigor: Show Checker Output**: derleme ve süreç hatalarının günlüğü.
- **Rigor: Restart Language Server**: arka plan sunucusunu yeniden başlatır.
- **Rigor: Show Check Details**: güncel dosyanın Rigor panelini açar.

`rigor.info.autoOpen`, sağ panelin dosya açıldığında otomatik görünmesini kontrol eder.

Pratik kurulum: proje kökünde `./install.sh vscode`. Diğer iki hedef ve betik
seçenekleri için [Kurulum rehberi](../../Docs/Install.md).

Varsayılan yürütülebilir dosya `${workspaceFolder}/.build/debug/SuuTensai`.
Eksikse `rigor.autoBuild` açıkken otomatik derlenir. Başka konum için
`rigor.checkerPath`, farklı Swift kurulumu için `rigor.swiftPath` ayarlanabilir.
`rigor.lint.enabled` kontrolü açıp kapatır; `rigor.lint.delay` isteğe bağlı
gecikmeyi belirler. Varsayılan `0` her düzenlemenin hemen gönderilmesini sağlar.
Eklenti shell komut metni üretmez; checker'ı ayrı argümanlarla çalıştırır.

## CLI ve F5

Telefon uygulaması CLI'nin yerine geçmez; aynı çekirdeği kullanır.
Eski `swift run SuuTensai ...` komutları, AST/token modları ve standart hata
çıktısı korunur. Projedeki F5 yapılandırmaları Debug/Release CLI'yi derleyip
çalıştırır. **Tasks: Run Task → Rigor: Check Current File** kaydedilmiş dosyayı
terminalde kontrol eder; canlı linter kaydedilmemiş metni de kullanır.

Canlı dil sunucusu ayrı bir CLI modudur:

```sh
.build/debug/SuuTensai --lsp
```

stdin/stdout üzerinde `Content-Length` çerçeveli JSON-RPC 2.0 ve LSP kullanır:
initialize/shutdown, didOpen/didChange/didClose ve publishDiagnostics desteklenir.
Belge senkronizasyonu tam metindir ve konumlar UTF-16'dır. VS Code istemcisi,
import bağımlılıklarını da sürümlemek için `rigor/sync` revizyonunu kullanır.
`rigor/status` bildirimleri ayrıntı panelini günceller; `rigor/check` isteği
güncel kontrol tamamlandığında yanıt döndürür.

Tek kontrol yapan JSON modu da kullanılabilir:

```sh
echo '{"filePath":"/absolute/main.rigor","source":"theorem id<A:Type>(x:A)->A { x }","overlays":{}}' | .build/debug/SuuTensai --lint-json
```

Bu mod stdout'a yalnızca JSON döndürür. JSON isteği başarıyla işlendiğinde,
ispat hatalı olsa bile çıkış kodu 0'dır; hatalar `diagnostics` içindedir.
Normal `--check` hatalı kaynakta yine 1 döndürür.

## Geliştirme testleri

```sh
bash Scripts/test.sh
node --test VSCode/rigor/test/*.test.js
ELECTRON_RUN_AS_NODE=1 '/Applications/Visual Studio Code.app/Contents/MacOS/Code' Scripts/test-vscode-grammar.cjs
```

`test/extension-host.js`, ayrı bir VS Code geliştirme profilinde gerçek
DiagnosticCollection, aynı sunucu sürecinin yeniden kullanılması, kaydedilmemiş
belge/import akışları, hızlı düzenlemeler ve Rigor panelini doğrular.
`test/lsp.test.js`, gerçek Swift sunucusunda protokol yaşam döngüsünü, iptali,
son sürümün korunmasını, import'ları ve parçalı UTF-8 mesajlarını kontrol eder.
TextMate testi, kurulu VS Code'un kendi tokenizer kitaplıklarını kullanır;
pakete bu kitaplıklar kopyalanmaz.

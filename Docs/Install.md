# Üç kurulum hedefi

Proje kökünde `./install.sh --help` komutuyla bütün seçenekleri görebilirsin.
Betikler çalışma dizininden bağımsızdır ve boşluk içeren dosya yollarını destekler.
Derleme çıktıları `.build` altında tutulur.

## CLI

Swift 6.4 veya üzeri gerekir. macOS'ta Xcode araçları, diğer desteklenen
platformlarda kurulu Swift toolchain kullanılır.

```sh
./install.sh cli
~/.local/bin/rigor --check Examples/kernel.rigor
```

Varsayılan kurulum release sürümünü `~/.local/bin/rigor` olarak kopyalar.
Bu dizin PATH'te değilse betik bilgi verir; shell ayarlarını otomatik değiştirmez.

```sh
./install.sh cli --prefix "$HOME/Applications/Rigor"
./install.sh cli --configuration debug
./install.sh cli --build-only
```

Yalnızca build seçeneğinin çıktısı `.build/artifacts/cli/rigor` dosyasıdır.
Kaynak üzerinden `swift run SuuTensai`, `--check`, `--ast`, `--tokens`,
`--parse-only`, `--lint-json` ve `--lsp` seçenekleri de kullanılabilir.

## VS Code

Swift, Python 3 ve VS Code gerekir. Eklenti Node.js'i VS Code'un kendi
çalışma zamanından kullanır; kurulumda npm paketi indirilmez.

```sh
./install.sh vscode
```

Betik debug checker'ı derler, manifest sürümünden VSIX oluşturur ve VS Code'a
kurar. Ardından VS Code'da **Developer: Reload Window** çalıştırıp bu proje
kökünü aç. `.rigor` dosyasının yanında sağda canlı checker sonucu görünür.
Paneli kapatırsan **Rigor: Show Check Details** komutuyla yeniden açabilirsin.

```sh
./install.sh vscode --package-only
./install.sh vscode --code "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
./install.sh vscode --skip-build
```

`--package-only`, `.build/rigor-language-<sürüm>.vsix` dosyasını hazırlar.
`--skip-build` yalnızca checker zaten güncelse kullanılmalıdır.

## iOS

macOS, Swift 6.4 içeren Xcode ve ilgili iOS SDK gerekir. Simülatör build'i
için Apple hesabı veya imzalama sertifikası gerekmez.

```sh
./install.sh ios
./install.sh ios --configuration Release
```

Çıktı `.build/iOS/Build/Products/<yapılandırma>-iphonesimulator/Rigor.app`.
Çalışan tek simülatöre kurup açmak veya belirli bir simülatör kullanmak için:

```sh
./install.sh ios --simulator --run
./install.sh ios --simulator SIMULATOR_UDID --run
./install.sh ios --list-devices
```

Gerçek iPhone'da geliştirici modu açık olmalı, telefon bilgisayarla eşleşmiş
olmalı ve Xcode'da Apple geliştirme hesabı bulunmalıdır.

```sh
./install.sh ios --device auto --run
./install.sh ios --device IPHONE_UDID --team APPLE_TEAM_ID --install
```

Tek fiziksel iOS cihazı ve tek geçerli Apple Development sertifikası varsa
`auto` bunları seçer. Birden fazla cihaz/takım varsa açıkça belirtmen gerekir.
`RIGOR_TEAM_ID` ortam değişkeniyle de takım seçilebilir. Takım, sertifika ve
cihaz kimliği kaynak dosyalara yazılmaz. Xcode standart otomatik imzalama
işlemini ve gerekli provisioning profilini yönetir.

İmzalı build `.build/iPhone/Build/Products/<yapılandırma>-iphoneos/Rigor.app`
altında oluşur. `--install` yükler, `--run` yükleyip açar; varsayılan yalnızca
build hazırlar. Kişisel geliştirici kurulumlarının geçerliliği kullanılan
provisioning profiline bağlıdır; süresi dolduğunda yeniden çalıştırılmalıdır.

## Testler

```sh
bash Scripts/test.sh
node --test VSCode/rigor/test/*.test.js
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/test-editor.sh
bash Scripts/test-ios.sh SIMULATOR_UDID
bash Scripts/test-ios.sh --device auto
```

Son komut, gerçek taslağı kullanmayan ayrı test oturumunda sembol şeridinin
kaydırılmasını, dokunulan sembolün eklenmesini ve klavye açıkken yatay editörü
XCUITest ile doğrular. Fiziksel cihaz testi de aynı ayrı taslak oturumunu kullanır.
Ekran görüntüleri `.build/iOS-UI-*.xcresult` raporundadır.

Kapalı iPhone Duo simülatörü yatay dönüşü uygulamadığında yalnızca yatay test
atlanır; sembol şeridi testi çalışır. Fiziksel cihazda XCUITest ayrı bir runner
uygulaması kurar. Ücretsiz geliştirici hesabının uygulama kotası doluysa bu
runner kurulamayabilir; normal Rigor güncellemesi aynı uygulama kimliğini kullanır.

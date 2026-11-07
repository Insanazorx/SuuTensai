# SuuTensai — Rigor

Rigor ispat/tür denetleyicisi; CLI, canlı VS Code eklentisi ve iPhone editörü.

```sh
./install.sh cli       # ~/.local/bin/rigor
./install.sh vscode    # checker + VS Code eklentisi
./install.sh ios       # iOS simülatör build'i
```

Bağlı iPhone'a kurup aç: `./install.sh ios --device auto --run`.
Seçenekler ve testler: [Kurulum rehberi](Docs/Install.md).

Kaynak → `Lexer` → `[Token]` → `Parser` → `Program` → `Kernel` → doğrulanmış `CoreTerm`.
Parser yalnızca sözdizimini, kernel isimleri, türleri ve ispat terimlerini kontrol
eder. Kernel adımlarını açıklayan Türkçe yorumlar içerir. Okuma rehberi:
[Docs/Kernel.md](Docs/Kernel.md).

## iPhone uygulaması

Küçük bir metin editörü ve cihaz üzerinde otomatik rigor checker için
`iOS/Rigor.xcodeproj` projesini Xcode ile aç. iOS 17+ sürümü, taslak kaydı,
hata konumuna gitme, örnekler ve dışa aktarma içerir.
Kurulum ve sınırlar: [iOS/README.md](iOS/README.md).
Checker artık `RigorCore` adlı Swift kütüphanesi olarak da kullanılabilir;
`swift run SuuTensai` komutları aynı şekilde çalışır.

## VS Code: CLI, linter ve renklendirme

CLI, telefon uygulamasıyla birlikte korunur. F5 yapılandırmaları Debug/Release
CLI'yi çalıştırır; `Ctrl+Shift+B` debug CLI'yi derler.
`.rigor` dosyalarında renklendirme ve kaydedilmemiş metni de kontrol eden
canlı linter için [Rigor VS Code eklentisini](VSCode/rigor/README.md) kur.
Eklenti kalıcı dil sunucusuyla her düzenlemeyi anında kontrol eder; Swift'e
benzer renklendirme ve güncel kontrol raporunu gösteren bir Rigor paneli içerir.
Yerel paket `python3 Scripts/package-vscode.py` ile üretilir.
Terminalde checker derlemek için `bash Scripts/build.sh debug` kullanılabilir.

## Çalıştırma

Swift 6.4 veya üzeri gerekir. Haricî bağımlılık yoktur.

```sh
swift run SuuTensai
swift run SuuTensai main.rigor
swift run SuuTensai Examples/reflexivity.rigor
swift run SuuTensai --tokens Examples/frontend.rigor
swift run SuuTensai --parse-only Examples/frontend.rigor
swift run SuuTensai --ast Examples/fundamentals-syntax.rigor
swift run SuuTensai --ast Examples/elimination.rigor
swift run SuuTensai --check main.rigor
swift run SuuTensai --check Examples/kernel.rigor
bash Scripts/test.sh
bash Scripts/test.sh -c release -debug-info-format none
```

Dosya verilmezse yerleşik örnek çalışır. `-` dosya adı UTF-8 stdin okur.
Varsayılan çalıştırma kernel kontrolüdür: `swift run SuuTensai main.rigor`.
Girintili yapısal AST için `--ast` kullan. `--tokens` yalnızca lexer'ı,
`--parse-only` lexer ve parser'ı çalıştırır. Hatalar dosya, satır, sütun ve
işaretçiyle stderr'e yazılır; çıkış kodu 1 olur. Başarılı parse ispat doğrulamaz.
`--check`, varsayılan davranışı açıkça seçer: kernel'i çalıştırır; import'ları
yükler ve kullanılan/tanımlanan aksiyomları raporlar. `--ast`, `--tokens` ve
`--parse-only` kernel'i çalıştırmaz.

VS Code'da `Debug SuuTensai` veya `Release SuuTensai` seçip F5
(debug) ya da Ctrl+F5 (debug olmadan çalıştır) kullan. Açılan kutuya proje
kökündeki script'in adını uzantısıyla yaz; varsayılan `main.rigor`.
Kökteki `main.rigor` çalışma taslağıdır; tamamlanmış ispat örnekleri
`Examples/reflexivity.rigor` ve `Examples/kernel.rigor` içindedir.
`Debug SuuTensai`, `Release SuuTensai` ve `Check Rigor (kernel)` yapılandırmalarının
hepsi kernel'i çalıştırır.
Geniş örneği görmek için script adına `Examples/kernel.rigor` yazabilirsin.

Normal kurulumlarda `swift test` kullanılabilir. `Scripts/test.sh`,
önbellekleri projenin `.build` dizininde tutar ve bazı Apple Swift 6.4 Command
Line Tools kurulumlarında bulunamayan Swift Testing makro eklentisinin yolunu
açıkça geçirir. Betik, bu projenin manifest'i için SwiftPM sandbox'ını kapatır.
Ek test seçeneklerini iletir: `bash Scripts/test.sh --filter StressTests`.
Yukarıdaki release komutu test derlemesinde debug sembolü üretimini kapatır.

## Sözdizimi

```rigor
theorem reflexivity<A: Type>(x: A) -> A {
    return x
}

def identity<A: Type>(x: A) -> A { x }
axiom refl<A: Type>(x: A) -> Eq<A>(x, x);

Gamma Base {
    A: Type;
    x: A
}
```

- Generic parametreler isteğe bağlıdır; yazıldıklarında boş olamazlar.
  Değer parametrelerinin `()` ayraçları zorunludur ve boş olabilir.
- Bütün parametrelerde tür yazılır: `x: A`. Son virgül kabul edilir.
  `_` parametre adı olarak kullanılabilir.
- `Gamma`, sıralı `ad: tür` bildirimlerinden oluşan bir kaynak düğümüdür.
  Parser çalışan bir bağlam oluşturmaz veya theorem'e otomatik bağlamaz.
- Gövdelerde `let x = value`, `let x: A = value`, `return value`,
  ifade cümleleri ve en sondaki sonuç ifadesi kullanılabilir.
- Cümlelerden sonra noktalı virgül, satır sonu veya kapanış süslü parantezi
  gerekir. `{ x; }` ifade cümlesi, `{ x }` sonuç ifadesi içerir.
- Satır sonları ifadeyi zorla kesmez: `f` ardından yeni satırda `(x)` hâlâ
  çağrıdır. Operatörler ve generic argümanlar da yeni satırda devam edebilir.
  Gerektiğinde açık noktalı virgül kullan.
- `return` değerinin yeni satırda başlaması mümkündür. Boş `return` reddedilir.
  Boş gövde ve `return` sonrasındaki cümleler sözdizimsel olarak kabul edilir.
  Bunların anlamını kernel belirler.
- Blok bildirimlerinden sonra isteğe bağlı noktalı virgül kullanılabilir.
  Aksiyomlar noktalı virgül, satır sonu veya dosya sonuyla ayrılır.

İfadeler:

```rigor
Type                             // tür evreni
Prop                             // önerme evreni
x                                // isim
_                                // çözülmemiş delik
123456789012345678901234567890     // kayıpsız sayı yazımı
"hello"                          // string
f(x, y)                          // değer argümanları
f<A, B>(x)                       // açık generic argümanları
F<G<A>>                          // iç içe generic uygulama
A -> B -> C                      // A -> (B -> C)
(x: A, y: B) -> P(x, y)           // bağımlı fonksiyon türü
fun (x: A, y: B) => f(x, y)       // lambda
{ let y = x; y }                 // blok ifadesi
```

Lambda için `fun` ve `func` aynı anlama gelir; ikisi de `Lambda` düğümü üretir.

`<` ve `>` yalnızca generic ayraçlarıdır. Karşılaştırma için şimdilik
`lt(x, y)` ve `gt(x, y)` gibi isimler kullanılır. `=` yalnızca let bağlama
işaretidir. Atama, member access, dizi literal'i, örtük argüman çıkarımı ve
taktik dili bu gramerin parçası değildir.

Operatörler, düşük öncelikten yükseğe:

| Operatör | Yön |
| --- | --- |
| `->` | sağ |
| mantıksal veya (iki dikey çizgi) | sol |
| `&&` | sol |
| `==`, `!=` | sol |
| `+`, `-` | sol |
| `*`, `/`, `%` | sol |
| önek `!`, `-`, `+` | önek |
| `^` | sağ |
| `<...>` ve `(...)` uygulamaları | sol |

`-x^2`, `-(x^2)` şeklindedir. Operatörlerin anlamı ve tipleri parser'da kodlanmaz.

İsimlerde Unicode XID kuralları ve alt çizgi kullanılır. Anahtar kelimeler
büyük/küçük harfe duyarlıdır; `Type2` bir isimdir. Sayılar ASCII rakamlarından
oluşur ve String olarak saklanır; makine tamsayısına dönüştürülüp taşırılmaz.
Ondalık/rasyonel literal sözdizimi henüz yoktur.

String'ler çift tırnaklıdır. Tırnak, ters eğik çizgi, n/r/t/0 kaçışları ve
`u{1...6 hex rakam}` Unicode kaçışları desteklenir. Ham satır sonları,
surrogate değerleri ve Unicode aralığını aşan kaçışlar hatadır.
`//` yorumları ve iç içe `/* ... */` yorumları desteklenir.
Satır sayacı LF, CR, CRLF, VT, FF, NEL, U+2028 ve U+2029'u tanır.

## AST'yi kernel'e bağlama

```swift
let tokens = try Lexer(source).tokenize()
let program = try Parser(tokens: tokens).parse()
// Kısayol: try Parser(source: source).parse()

for declaration in program.declarations {
    switch declaration {
    case .theorem(let theorem):
        let signature = theorem.signature
        // signature.genericParameters: [Parameter]
        // signature.parameters: [Parameter]
        // signature.returnType: Expression
        // theorem.body.statements: [Statement]
        // theorem.body.result: Expression?
        // İspat kontrolü için aşağıdaki Kernel.check API'sini kullan.
        _ = signature
    case .definition, .axiom, .context, .inductive, .import:
        break
    }
}

let report = try Kernel().check(program) // importsuz bağımsız AST
// Dosya ve import'lar: try RigorLoader(kernel: Kernel()).checkFile(fileURL)
```

`Program` sıralı bildirimleri, `Signature` imzayı, `Block` gövdeyi taşır.
`StatementKind` yerel bağlamayı, return'ü ve ifade cümlesini ayırır.
`ExpressionKind` türler ve terimler için ortak ağaçtır: `A`, `F<A>`, fonksiyon
türleri ve ispat terimleri aynı sözdizimi ailesindedir. İfadenin gerçekten tür
olup olmadığını kernel belirler. İsimler korunur; de Bruijn indekslerine
dönüştürülmez. Tekrarlanan veya tanımsız adlar parser tarafından reddedilmez.

Her AST düğümü `SourceSpan` taşır. Aralıklar yarı açıktır; ofsetler UTF-8
baytı, satır ve sütunlar 1 tabanlıdır. Sütunlar Unicode scalar sayar.
Yorumlar AST'de tutulmaz; parantezler iç ifadenin aralığını genişletir.
`FrontendError` lexer/parser aşamasını, mesajı ve kaynak aralığını taşır.

`astDescription`, Program'dan başlayarak bütün bildirim, cümle, ifade ve
pattern alt düğümlerini ayrı satırlarda gösterir. Örneğin `return match ...`,
`Return -> Match -> Scrutinee / Motive / Cases` şeklinde bir ağaçtır.
Motive bir lambda ise parametreleri ve gövdesi; her dalda pattern, constructor
alanları ve gövde ayrı ayrı yazdırılır. Aynı yapısal çıktı tek bir düğümün
`astDescription` özelliğinden de alınabilir.

Kısa, kaynak benzeri gösterim gerektiğinde ifade/cümle/pattern için
`sourceDescription` kullan. Bu çıktı öncelik incelemesine uygundur; AST ağacı
veya kayıpsız kaynak serialization'ı değildir.

`Kernel.check` bildirimleri sırayla doğrular. `infer` ifade ve türünü üretir;
`check(expression, against: type, in: context)` beklenen türe göre kontrol eder.
Kernel'in iç temsili `CoreTerm`'dür. Kaynak düzeyindeki `Type`/`Term` alias'ları
`Expression` olarak kalır. `AstWalker` sözdizimsel araçlar için korunur; kernel
bağlam ve beklenen tür taşıyan ayrı fonksiyonlar kullanır.

## Minimum DTT desteğinin programlama karşılıkları

| İhtiyaç | Programlama karşılığı | Kaynak sözdizimi |
| --- | --- | --- |
| Evren seviyeleri | Türlerin türünü belirtmek | `Type`, `Type(0)`, `Type(1)` |
| Bağımlı fonksiyon | Sonuç türü değere bağlı fonksiyon | `(x: A) -> P(x)` |
| Lambda ve uygulama | Fonksiyon ve çağrı | `fun (x: A) => x`, `f(x)` |
| Yerel kapsam | Parametreler ve yerel bağlamalar | `let x: A = value` |
| İndüktif tür | Recursive enum / algebraic data type | `inductive Nat: Type { ... }` |
| İndeksli aile | Bağımlı tür ailesi / GADT benzeri yapı | `inductive Id<A: Type>(x: A, y: A): Type { ... }` |
| Eliminasyon | Pattern matching | `match value { left(x) => f(x); ... }` |
| Bağımlı eliminasyon | Açık sonuç türü ailesi, motive | `match n return fun (k: Nat) => P(k) { ... }` |
| İndüksiyon | Genel recursor çağrısı | `NatInd(motive, base, step, n)` |
| Dosyada tekrar kullanım | Import bildirimi | `import "Fundamentals.rigor";` |

Son dört yapının AST'si kaynak niyetini korur. Parser recursor üretmez,
pattern'leri çalıştırmaz, dosya yüklemez veya doğruluk kararı vermez.
`--check` modunda kernel doğrudan recursive indüktif aileleri doğrular,
`AileAdıInd` recursor'unu üretir ve match/recursor hesaplamalarını indirger.

### Evrenler

`Type`, `Type(0)` kısaltmasıdır. `Universe.type(level: Int)` seviyeyi saklar.
Bu ilk sürümde seviye, Swift Int aralığına sığan negatif olmayan bir tamsayı
literal'idir. `Type(u)` ve `Type(1 + 1)` desteklenmez. Sıradan sayı literal'leri
String olarak kayıpsız saklanmaya devam eder.
Kernel `Type(n):Type(n+1)` ve impredicative `Prop` kurallarını uygular.
Evrenler otomatik yükseltilmez; evren polimorfizmi yoktur. Prop'tan Type'a
eliminasyon bu sürümde reddedilir. Parser evren doğrulaması yapmaz.

### İndüktif tanımlar

```rigor
inductive Nat: Type {
    zero: Nat;
    succ: Nat -> Nat;
}

inductive Id<A: Type>(x: A, y: A): Type {
    refl: (value: A) -> Id<A>(value, value);
}
```

`<...>` içindekiler uniform parametreler, `(...)` içindekiler değişebilen
indekslerdir. İki liste de isteğe bağlıdır; generic listesi yazılırsa boş olamaz.
Uniform parametrelerin tür olması zorunlu değildir: örneğin
`<A: Type, fixed: A>` de sözdizimsel olarak kabul edilir.
Sort'tan sonra constructor imzaları gelir. Constructor'lar noktalı virgül veya
satır sonuyla ayrılır; son constructor'dan sonra kapanış ayırıcı olarak yeterlidir.
`inductive Empty: Type {}` gibi boş aileler de desteklenir.

`InductiveDeclaration` içinde `parameters`, `indices`, `sort` ve
`constructors` ayrı alanlardır. Constructor tipi, normal Expression ağacıdır.
Doğru aileye dönüş, uniform parametreler ve alanların evrenleri kernel'de kontrol
edilir. Positivity kontrolü bilinçli olarak dardır: recursive alan doğrudan
`List<A>` gibi aynı aile olmalıdır. Negatif, nested ve fonksiyonla taşınan
recursive oluşumlar reddedilir. Mutual inductive desteği yoktur.

### Pattern matching ve motive

```rigor
match value {
    left(a) => fromA(a);
    right(b) => fromB(b);
}

match n return fun (value: Nat) => P(value) {
    zero => base;
    succ(k) => step(k);
}
```

`MatchExpression`, `scrutinee`, isteğe bağlı `motive` ve `cases` taşır.
Motive normal bir Expression'dır; indeksli eliminasyon için indeksleri ve
hedef kanıtı birlikte bağlayan bir lambda yazabilirsin. Motive'in uygun türünü
kontrol etmek veya eksik motive'i çıkarmak parser'ın görevi değildir.

Dallar noktalı virgül, virgül veya ifade bittikten sonraki satır sonuyla ayrılır.
Dalın gövdesi herhangi bir ifade olabilir; yerel cümleler için blok kullan:
`left(a) => { let result = f(a); result }`.
Boş `match impossible return fun (e: Empty) => A {}` sözdizimi kabul edilir.

Pattern çeşitleri:

- `name`: çözülmemiş çıplak ad; constructor mı bağlayıcı mı olduğunu sonraki
  sembol çözümleme aşaması belirler.
- `constructor(p1, p2)`: açık constructor pattern'i; iç içe olabilir.
  Sıfır alanlı constructor'ı açık belirtmek için `zero()` kullanılabilir.
- `_`: wildcard.

Örnek: `cons(pair(head, _), tail)`. Son virgül desteklenir.
Literal pattern'leri, guard'lar ve or-pattern'ler bu minimum sürümde yoktur.
Kernel constructor varlığı/arity'si, pattern kapsamı, tekrar eden adlar ve
kapsayıcılığı denetler. Kernel'in mevcut alt kümesinde nested pattern yerine
ayrı iç match gerekir. İndeksli dependent match için motive bütün indeksleri
ve en son hedefi alır. Otomatik indeks unification yapılmaz.
İndüksiyon varsayımı match dalına otomatik eklenmez; genel recursor çağrısında
her recursive alandan sonra bir `ih` argümanı gelir.

### Import ve recursor sınırı

`import "Fundamentals.rigor";`, decoded dosya yolunu bir
`ImportDeclaration` olarak saklar. AST modunda dosya yüklenmez. `--check` modunda
`RigorLoader` yolları import eden dosyaya göre çözer, döngüleri reddeder ve aynı
dosyayı bir kez yükler. İsimler ortak global ortamda tutulur; namespace yoktur.
Herhangi bir hata, o yükleme işlemindeki bütün ortam değişikliklerini geri alır.

`NatInd` veya `IdInd` gibi recursor adları sıradan identifier'lardır.
Parser bunları özel olarak tanımaz; mevcut çağrı/lambda sözdizimi yeterlidir.
Kernel `AileAdıInd(parametreler..., motive, constructorMetotları..., indeksler..., hedef)`
imzasını üretir. Type ailesinin recursor'u Type(0)'a, Prop ailesininki Prop'a
elimine eder. Açık match, Type ailelerinde daha büyük evrenlere de gidebilir.
`Fundamentals.rigor`, Id/refl'i indüktif olarak; J/transport/congruence'ı sıradan
def/theorem olarak tanımlar. `Examples/kernel.rigor` eliminasyon, hesaplama ve
indüksiyonla ispat örneklerini içerir.

## Dayanıklılık ve testler

Lexer tek ileri tarama yapar; kalan kaynak her token'da yeniden kopyalanmaz.
Parser boş ve EOF'siz token dizilerini kabul eder; ortadaki sahte EOF'yi
reddeder. Aynı lexer/parser tekrar çağrıldığında yeni tarama başlar.
İlk hatada `FrontendError` döner; çoklu hata toplama/kurtarma henüz yoktur.
Çok derin ifadeler kontrollü hata verir. Varsayılan sınır 32'dir;
`maxNesting` 1...32 aralığına sınırlanır. Debug Swift Testing'in küçük thread
stack'lerinde de güvenli kalması için bu tavan bilinçli olarak düşüktür.
`maxNesting` çağrı derinliğinin yanında
uzun sol işlem ve çağrı zincirlerinin AST yüksekliğini de sınırlar.
Geniş listeler derinlik tüketmez. Toplam dosya büyüklüğüne kota konmaz;
bellek kullanımı kaynak ve AST büyüklüğüyle artar.

Testler:

- 10.000 theorem, 2.000 parametre/argüman, 5.000 yerel bağlama;
- 10.000 iç içe yorum, 100.000 karakterlik isim, uzun whitespace/yorumlar;
- 20.000 basamaklı sayı; Unicode, kaçışlar ve kaynak konumları;
- çok derin parantez, generic, blok, önek, ok ve işlem/çağrı zincirleri;
- bağımsız yapısal modelle karşılaştırılan 1.000 üretilmiş ifade;
- örneklerin her kesilme noktası, eski gramer için 2.000 ve yeni gramer için
  2.000 deterministik mutasyon, 3.000 rastgele metin ve 1.000 bozuk token dizisi;
- açık evren seviyeleri, indeksli aileler, motive'ler ve boş match ifadeleri;
- 2.000 constructor/dal/pattern alanı ile genişlik, 10.000 seviyeli
  match/pattern girdileriyle derinlik; ifadelerle pattern'lerin ortak stack bütçesi.

Rastgele testlerin tohumu sabittir; aynı girdilerle tekrarlanabilir.

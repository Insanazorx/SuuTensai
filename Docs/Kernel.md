# Kernel'i okuyarak öğrenme rehberi

Bu, küçük bir bağımlı tip teorisi uygulamasıdır. Bağımsız denetimden geçmiş bir
üretim ispat asistanı değildir. Desteklenmeyen yazımları kabul etmek yerine hata
verir; parser'ın daha geniş bir dil kabul etmesi normaldir.

## Nereden başlamalı?

1. `Sources/SuuTensai/Kernel.swift`: ortam, bildirimlerin kontrol sırası,
   parametrelerin bağlanması ve hatada ortamın geri alınması.
2. `Sources/SuuTensai/Core/CoreTerm.swift`: küçük iç dil. Çok parametreli
   fonksiyonlar iç içe tek parametreli Pi/lambda; generic uygulama da uygulamadır.
3. `Sources/SuuTensai/Gamma.swift`: yerel bağlam. İç kapsamın dış kapsamı
   değiştirmemesi ve aynı yazılan iki değişkenin farklı kimlikleri.
4. `Sources/SuuTensai/Core/Elaboration.swift`: `infer`, `check`, bloklar ve evrenler.
5. `Sources/SuuTensai/Core/Reduction.swift`: substitution, indirgeme ve eşitlik.
6. `Sources/SuuTensai/Core/Inductives.swift`: indüktif bildirim ve recursor üretimi.
7. `Sources/SuuTensai/Core/Elimination.swift`: motive ve her dalın beklenen türü.
8. `Fundamentals.rigor`, ardından `Examples/kernel.rigor`: bu kurallarla yazılan
   eşitlik, taşıma, eliminasyon ve indüksiyon ispatları.

Kodun bu bölümlerinde her temel hamlenin nedenini Türkçe yorumlarla anlattık.
`AstWalker` bir sözdizimsel araç arayüzü olarak durur. Tür kontrolü sıradan
ziyaretçiden farklı olarak Γ ve beklenen türü her adımda taşır.

## İki temel soru

`infer(e, in: Γ)`, “e'nin türü nedir?” sorusuna `(terim, tür)` üretir.
`check(e, against: T, in: Γ)`, “e, T tipinde mi?” sorusunu doğrular veya hata verir.

Örneğin `f : (x:A)->P(x)` ve `a:A` ise uygulama kuralı:

```text
infer(f) = (f, (x:A)->P(x))
check(a, A)
infer(f(a)) = (f(a), P(a))
```

Son satırda `P(x)` içine `a` konur. Aynı yerine koyma, lambda hesaplamasında
`(func(x:A)=>body)(a)` ifadesini `body[x:=a]` yapar. Değişken yakalamamak için
bağlayıcı kimlikleri tazelenir. `let` değerleri bağlama gerçek core değerleriyle
eklenir; yerel isimler blok dışına sızmaz.

`return` bu dilde bir ispat teriminin sonucudur. Gövdede sonuç bulunmalı ve
return sonrasında ifade olmamalıdır. Blokların son ifadesi de aynı işi yapar.
`def f()->A` sıfır parametreli bir core sabitidir; `f()` boş uygulaması silinir.

## Eşitlik ve evrenler

Kernel'in tanımsal eşitliği alpha-renaming, beta (lambda), delta (def/theorem
açma), zeta (yerel let) ve iota (match/recursor) hesaplamalarını kullanır.
Eta ve proof irrelevance uygulanmaz. Evrenler kümülatif değildir:
`Type(0):Type(1)` geçer; `Type(0):Type(0)` ve otomatik `Type(2)` yükseltmesi geçmez.
Type Pi'ları domain/codomain evrenlerinin maksimumunu, Prop Pi'ları Prop'u alır.

Bu kurallar için kullanılan temel referans:
[Lean evren kuralları](https://lean-lang.org/doc/reference/latest/The-Type-System/Universes/).
Lean'in tüm eşitlik kurallarının burada uygulandığı anlamına gelmez.

`Id<A>(x,y)` bu hesapsal eşitlik değildir. `Id` kaynak dilindeki bir indüktif
tip; onun kanıtları `Fundamentals.rigor` içindeki `refl`, `J`, `transport`
ile kullanılır. Kernel bu isimlere bakarak özel karar vermez.

## Match ve indüksiyon

`match e return motive { ctor(fields)=>body; ... }` kontrol edilirken:

1. e'nin doğrulanmış indüktif türü bulunur.
2. Motive'in indeksleri ve hedefi alıp bir tip verdiği denetlenir.
3. Constructor alanları her dal için taze değişkenlerle bağlanır.
4. O dalın hedefi `motive(constructorSonuçİndeksleri..., ctor(fields))` olur.
5. Gövde bu tipe göre kontrol edilir; eksik/tekrarlanan dallar reddedilir.

Motive yazılmadığında beklenen türden sabit bir motive kurulur. Bu yaklaşım
otomatik dependent motive çıkarımı veya indeks unification yapmaz. Geçerli
bazı ispatlarda açık motive yazmak gerekir. Nested pattern yerine iç match
kullan; kernel şu an flat constructor pattern, wildcard ve son catch-all destekler.

Her `I` indüktifi `IInd` üretir. Örneğin Nat için:

```text
NatInd : (P:Nat->Type)
      -> P(zero)
      -> ((k:Nat, ih:P(k))->P(succ(k)))
      -> (n:Nat)->P(n)

NatInd(P, base, step, zero)    = base
NatInd(P, base, step, succ(k)) = step(k, NatInd(P,base,step,k))
```

Kodda bu kurallar Nat adına bağlı değildir. Her doğrudan recursive alanın
ardına o alanın `ih` değeri eklenir; indeksli Vec ve birden fazla recursive
alanı olan Tree de aynı mekanizmayı kullanır. Metot sırası constructor yazım
sırasıdır. Generic aile parametreleri en başa, indeksler ve hedef en sona gelir.
Bu tasarımın referansı:
[İndüktif tipler ve recursor'lar](https://lean-lang.org/doc/reference/latest/The-Type-System/Inductive-Types/).

## Bilinçli sınırlar

- Recursor evren polimorfizmi henüz yok: Type ailesinin `Ind` hedefi Type(0),
  Prop ailesininki Prop. Type ailesine açık match daha yüksek Type'a gidebilir.
- Prop'tan Type'a eliminasyona hiçbir istisna tanınmaz; proof irrelevance yoktur.
- Strict positivity için dar bir alt küme kullanılır: recursive alan doğrudan
  aynı aile olmalı ve uniform parametreleri değiştirmemeli. Nested, mutual ve
  fonksiyonla taşınan recursion reddedilir.
- Genel recursion/ileri referans yoktur; recursive hesaplar `IInd` kullanır.
- Örtük argüman, evren polimorfizmi, tactic, literal/operatör anlamı yoktur.
  `zero`, `succ` ve tanımlı fonksiyon çağrılarını kullan.
- Varsayılan bütçe 1.000.000 adım, core çağrı derinliği 64, bağlayıcı listesi
  32'dir. Büyük ama doğru girdiler de sınır hatası alabilir; hata ispat kabulü
  anlamına gelmez. `KernelLimits` test/uygulama tarafından ayarlanabilir.

`axiom` açık bir varsayımdır. Her global kaydı aksiyom bağımlılıklarını saklar;
Varsayılan çalıştırma (veya açık `--check`) bunları raporlar. `--ast`, `--tokens`
ve `--parse-only` yalnızca sözdizimi araçlarıdır; kernel'i çalıştırmaz.
`Fundamentals.rigor` ve kernel örneği aksiyomsuzdur.
Import'lar `RigorLoader` tarafından dosyaya göre göreli çözülür. Namespace yoktur;
çakışan global isimler reddedilir. Döngü veya herhangi bir doğrulama hatası tüm
yüklemenin ortam değişikliklerini geri alır.

```sh
swift run SuuTensai --check main.rigor
swift run SuuTensai --check Examples/kernel.rigor
bash Scripts/test.sh
```

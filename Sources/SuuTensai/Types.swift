// Kaynak AST'sinde tipler de ifadedir. Kernel ise isim çözümlemesinden sonra
// CoreTerm kullanır; bu alias'lar doğrulanmış core tipleri anlamına gelmez.
public typealias Type = Expression
public typealias Term = Expression

use Channel;

var chan1 = new chan(int, 1);
var chan2 = new chan(int, 1);

var x1, x2 : int;

var arr : [0..#2] shared BaseClass = [new shared SelCase(x1, chan1, 0) : BaseClass, new shared SelCase(x2, chan2, 0) : BaseClass];

chan1.send(5);
chan2.send(4);

selectProcess(arr);

writeln(x1);
writeln(x2);

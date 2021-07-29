use Channel;

var chan1 = new chan(int, 1);
var chan2 = new chan(int, 1);

var x1, x2 : int;

var arr : [0..#2] shared SelBaseClass = [new shared SelCase(x1, chan1, selOperation.recv) : SelBaseClass, new shared SelCase(x2, chan2, selOperation.recv) : SelBaseClass];

chan1.send(5);
chan2.send(4);

selectProcess(arr);

writeln(x1);
writeln(x2);

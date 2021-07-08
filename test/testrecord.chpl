use Channel;

record r1 {
    var x, y : int;
}

var chan1 = new chan(r1);

begin {
    chan1.send(new r1(1, 2));
}

var (r3, ok) = chan1.recv();
writeln(r3);
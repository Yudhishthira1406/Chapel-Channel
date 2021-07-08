use Channel;
config const n = 100;

var chan1 = new chan(int, 1);

var total1, total2 : atomic int;
coforall i in 1..n {
    if i % 2 == 0 {
        chan1.send(i);
        total1.add(i);
        // writeln("Task ", i, " sent");
    }
    else {
        // writeln("Task ", i, " received ", chan1.recv());
        var (x, ok) = chan1.recv();
        total2.add(x);
    }
}

var totalSent = total1.read();
var totalReceived = total2.read();
writeln(totalSent == totalReceived);
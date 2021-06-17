use Channel;
config const n = 100;

var chan1 = new chan(int, 1);
coforall i in 1..n {
    if i % 2 == 0 {
        chan1.send(i);
        // writeln("Task ", i, " sent");
    }
    else {
        // writeln("Task ", i, " received ", chan1.recv());
        chan1.recv();
    }
}
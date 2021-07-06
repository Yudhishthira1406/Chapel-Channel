use Channel;

var chan1 = new chan(int);


begin {
    chan1.send(1);
    chan1.close();
}
var x = chan1.recv();

var y = chan1.recv();

writeln(x, y);




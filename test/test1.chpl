use Channel; 

var chan1 = new chan(int);

begin {
   chan1.send(5);
}

var (recv1, ok1) = chan1.recv();
writeln("Received unbuffered ", recv1);

var chan2 = new chan(int, 5);

begin {
   chan2.send(4);
}

var (recv2, ok) = chan2.recv();
writeln("Received buffered ", recv2);



use Channel; 

var chan1 = new chan(int);

begin {
   chan1.send(5);
}
writeln("Received unbuffered ", chan1.recv());

var chan2 = new chan(int, 5);

begin {
   chan2.send(4);
}

writeln("Received buffered ", chan2.recv());



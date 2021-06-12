use Channel; 

var chan1 = new chan(int, 5);

begin {
   chan1.send(5);
}
 writeln("Received ", chan1.recv());



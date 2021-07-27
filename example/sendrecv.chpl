use Channel;

config const size = 5;

// Create an integer channel with maximum capacity `size`
var chan1 = new chan(int, 5);

proc sender(channel : chan) {
    const valuetoSend = 100;
    channel.send(valuetoSend);
}

begin sender(chan1); // New task to send a value

var received : int;
chan1.recv(received); // Receive the first available value
writeln("Received ", received);

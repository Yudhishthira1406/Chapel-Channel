use Channel;

const debug = true;
var chan1 = new chan(int);
begin {
    try! {
        chan1.send(5);
    } catch e {
        if debug then writeln("Error: ", e.message());
    }
}

chan1.close();
var x : int;
var ok = chan1.recv(x);
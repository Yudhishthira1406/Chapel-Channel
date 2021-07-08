use Channel;

const debug = false;
var chan1 = new chan(int);
begin {
    try! {
        chan1.send(5);
    } catch e {
        if debug then writeln(e.message());
    }
}

chan1.close();

var (x, ok) = chan1.recv();
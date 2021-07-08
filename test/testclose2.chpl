use Channel;

var chan1 = new chan(int);

chan1.close();
try {
    chan1.close();
} catch e {
    writeln(e.message());
}
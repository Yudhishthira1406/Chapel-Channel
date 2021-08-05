use Channel;

var chan1 = new chan(int);

begin {
    {
        cobegin {
            chan1.send(5);
            chan1.send(6);
            chan1.send(8);
            chan1.send(10);
        }
        chan1.close();
    }
}

for i in chan1 {
    writeln(i);
}
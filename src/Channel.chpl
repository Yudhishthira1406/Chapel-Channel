/* Documentation for Channel */
module Channel {

    use LinkedLists;

    class Waiter {
        
        var process$ : single bool;
        var x;
        

        proc init(x1) {
            x = x1;
            
        }

        proc suspend() {
            process$.readFF();
        }

        proc release() {
            process$.writeEF(true);
        }
    }

    class chan {
        type eltType;
        var bufferSize : int;
        var buffer : [0..#bufferSize] eltType;
        var sendidx = 0;
        var recvidx = 0;
        var count = 0;

        var sendWaiters : LinkedList(shared Waiter);
        var recvWaiters : LinkedList(shared Waiter);

        var lock$ : sync bool;

        proc init(type elt, size = 0) {
            eltType = elt;
            bufferSize = size;
            sendWaiters = new LinkedList(shared Waiter(eltType));
            recvWaiters = new LinkedList(shared Waiter(eltType));
        }

        proc lock() {
            lock$.writeEF(true);
        }

        proc unlock() {
            lock$.readFE();
        }

        proc recv() : eltType {
            
            lock();
            
            var x : eltType;
            if count == 0 {
                var processing = new shared Waiter(x);
                recvWaiters.push_back(processing);
                
                unlock();
                processing.suspend();
                x = processing.x;
                return x;
            }

            x = buffer[recvidx];
            
            if sendWaiters.size > 0 {

                var sender = sendWaiters.pop_front();
                if bufferSize > 0 {
                    buffer[recvidx] = sender.x;

                    sendidx = (sendidx + 1) % bufferSize;
                    recvidx = (recvidx + 1) % bufferSize;
                }

                sender.release();
            }

            else {

                recvidx = (recvidx + 1) % bufferSize;
                count -= 1;

            }

            unlock();

            return x;

        }

        proc send(val : eltType) {
            lock();

            if count == bufferSize {
                var processing = new shared Waiter(val);
                
                sendWaiters.push_back(processing);

                unlock();

                processing.suspend();
            }

            else {
                if recvWaiters.size > 0 {

                    var receiver = recvWaiters.pop_front();
                    receiver.x = val;

                    receiver.release();
                }

                else {
                    buffer[sendidx] = val;

                    sendidx = (sendidx + 1) % bufferSize;
                    count += 1;
                }

                unlock();
            }
        }


    }
    
}

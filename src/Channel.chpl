/* Documentation for Channel */
module Channel {

    use LinkedLists;

    class Waiter {
        
        var process$ : single bool;
        var x; 

        proc init(x1) {
            x = x1;    
        }

        proc suspend() : bool {
            return process$.readFF();
        }

        proc release(status : bool) {
            process$.writeEF(status);
        }
    }

    class chan {
        type eltType;
        var bufferSize : int;
        var buffer : [0..#bufferSize] eltType;
        var sendidx = 0;
        var recvidx = 0;
        var count = 0;
        var closed = false;

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

        proc recv() : (eltType, bool) {
            lock();
            
            var x : eltType;

            if closed && count == 0 {
                unlock();
                return (x, false);
            }

            if count == 0 && sendWaiters.size == 0 {
                var processing = new shared Waiter(x);
                recvWaiters.push_back(processing);
                
                unlock();
                if processing.suspend() == false {
                    return (x, false);
                }
                x = processing.x;
                return (x, true);
            }

            if bufferSize > 0 {
                x = buffer[recvidx];
            }

            if !closed && sendWaiters.size > 0 {

                var sender = sendWaiters.pop_front();
                if bufferSize > 0 {
                    buffer[recvidx] = sender.x;

                    sendidx = (sendidx + 1) % bufferSize;
                    recvidx = (recvidx + 1) % bufferSize;
                }
                else x = sender.x;

                sender.release(true);
            }

            else {

                recvidx = (recvidx + 1) % bufferSize;
                count -= 1;

            }
            unlock();

            return (x, true);

        }

        proc send(val : eltType) throws {
            lock();

            if closed {
                throw new owned ChannelError("Sending on a closed channel");
            }

            if count == bufferSize && recvWaiters.size == 0 {
                var processing = new shared Waiter(val);
                
                sendWaiters.push_back(processing);

                unlock();
                if processing.suspend() == false {
                    throw new owned ChannelError("Sending on a closed channel");
                }

            }

            else {
                if recvWaiters.size > 0 {

                    var receiver = recvWaiters.pop_front();
                    receiver.x = val;

                    receiver.release(true);
                }
                else {
                    buffer[sendidx] = val;

                    sendidx = (sendidx + 1) % bufferSize;
                    count += 1;
                }

                unlock();
            }
        }

        proc close() throws {

            lock();
            if closed {
                unlock();
                throw new owned ChannelError("Closing a closed channel");
            }
            closed = true;
            unlock();

            while(recvWaiters.size > 0) {
                var receiver = recvWaiters.pop_front();
                receiver.release(false);
            }

            while(sendWaiters.size > 0) {
                var sender = sendWaiters.pop_front();
                sender.release(false);
            }
        }
    }

    class ChannelError : Error {
        var msg:string;

        proc init(msg: string) {
            this.msg = msg;
        }

        override proc message() {
            return msg;
    }
}

}

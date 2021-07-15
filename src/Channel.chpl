/* Documentation for Channel */

module Channel {

    use LinkedLists;
    use CPtr;

    class Waiter {
        type valueType;
        var val : c_ptr(valueType);
        var processPtr : c_ptr(single bool);
        var isSelect : bool;
        var isSelectDone : c_ptr(atomic bool); 

        var prev : unmanaged Waiter?;
        var next : unmanaged Waiter?;

        proc init(ref value) {
            valueType = value.type;
            val = c_ptrTo(value);
            var process$ : single bool;
            processPtr = c_ptrTo(process$);
            isSelect = false;
        }

        proc init(ref value, ref process$ : single bool, ref selDone : atomic bool) {
            valueType = value.type;
            val = c_ptrTo(value);
            processPtr = c_ptrTo(process$);
            isSelect = true;
            isSelectDone = c_ptrTo(selDone);
        }

        proc suspend() : bool {
            return processPtr.deref().readFF();
        }

        proc release(status : bool) {
            processPtr.deref().writeEF(status);
        }
    }

    class WaiterQue {
        var front : unmanaged Waiter?;
        var back : unmanaged Waiter?;

        proc enque(waiter : Waiter) {
            if(front == nil) {
                front = waiter;
                back = waiter;
            }
            else {
                back.next = waiter;
                waiter.prev = back;
                back = waiter;
            }
        }

        proc isEmpty() : bool{
            return (front == nil);
        }

        proc deque() : Waiter {
            if front == nil {
                // Error
                writeln("Error");
            }
            else if front == back {
                var waiter = front;
                front = nil;
                back = nil;
                return waiter;
            }
            else {
                var waiter = front;
                front = front.next;
                front.back = nil;
                waiter.next = nil;
                return waiter;
            }
        }

        proc deque(waiter : Waiter) {
            if waiter == first {
                deque();
            }
            else if waiter == back {
                back = back.prev;
                back.next = nil;
            }
            else if waiter.prev && waiter.next {
                waiter.prev.next = waiter.next;
                waiter.next.prev = waiter.prev;
            }

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

        var sendWaiters : WaiterQue;
        var recvWaiters : WaiterQue;

        var lock$ : sync bool;

        proc init(type elt, size = 0) {
            eltType = elt;
            bufferSize = size;
            sendWaiters = new WaiterQue();
            recvWaiters = new WaiterQue();
        }

        proc lock() {
            lock$.writeEF(true);
        }

        proc unlock() {
            lock$.readFE();
        }

        proc recv(out val : eltType) : bool {
            lock();

            if closed && count == 0 {
                unlock();
                return false;
            }

            if count == 0 && sendWaiters.isEmpty() {
                var processing = new unmanaged Waiter(val);
                recvWaiters.enque(processing);
                
                unlock();
                return processing.suspend();
            }

            if bufferSize > 0 {
                val = buffer[recvidx];
            }

            if !closed && !sendWaiters.isEmpty() {

                var sender = sendWaiters.deque();
                if bufferSize > 0 {
                    buffer[recvidx] = sender.val.deref();

                    sendidx = (sendidx + 1) % bufferSize;
                    recvidx = (recvidx + 1) % bufferSize;
                }
                else val = sender.val.deref();

                sender.release(true);
            }

            else {

                recvidx = (recvidx + 1) % bufferSize;
                count -= 1;

            }
            unlock();

            return true;

        }

        proc send(val : eltType) throws {
            lock();

            if closed {
                throw new owned ChannelError("Sending on a closed channel");
            }

            if count == bufferSize && recvWaiters.empty() {
                var processing = new unmanaged Waiter(val);
                
                sendWaiters.enque(processing);

                unlock();
                if processing.suspend() == false {
                    throw new owned ChannelError("Sending on a closed channel");
                }

            }

            else {
                if !recvWaiters.isEmpty() {

                    var receiver = recvWaiters.deque();
                    receiver.val.deref() = val;

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

            while(!recvWaiters.isEmpty()) {
                var receiver = recvWaiters.deque();
                receiver.release(false);
            }

            while(!sendWaiters.isEmpty()) {
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

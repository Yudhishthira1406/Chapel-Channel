/* Documentation for Channel */

module Channel {

    use CPtr;
    use Sort;
    use SysCTypes;
    use List;
    use Random;

    class Waiter {
        type valueType;
        var val : c_ptr(valueType);
        var processPtr : c_ptr(single bool);
        var isSelect : bool;
        var isSelectDone : c_ptr(atomic bool); 

        var prev : unmanaged Waiter(valueType)?;
        var next : unmanaged Waiter(valueType)?;

        proc init(ref value, ref process$ : single bool) {
            valueType = value.type;
            val = c_ptrTo(value);
            processPtr = c_ptrTo(process$);
            isSelect = false;
        }

        proc init(ref value, ref process$ : single bool, ref selDone : atomic bool) {
            valueType = value.eltType;
            val = value;
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
        type eltType;
        var front : unmanaged Waiter(eltType)?;
        var back : unmanaged Waiter(eltType)?;

        proc enque(waiter : unmanaged Waiter(eltType)) {
            if front == nil {
                front = waiter;
                back = waiter;
            }
            else {
                back!.next = waiter;
                waiter.prev = back;
                back = waiter;
            }
        }

        proc isEmpty() : bool{
            return (front == nil);
        }

        proc deque() : unmanaged Waiter(eltType) {
            var waiter : unmanaged Waiter(eltType)?;
            if front == nil {
                // Error
                writeln("Error");
            }
            else if front == back {
                waiter = front;
                front = nil;
                back = nil;
            }
            else {
                waiter = front;
                front = front!.next;
                front!.prev = nil;
                waiter!.next = nil;
            }
            return waiter!;
        }

        proc deque(waiter : unmanaged Waiter(eltType)) {
            if waiter == front {
                deque();
            }
            else if waiter == back {
                back = back!.prev;
                back!.next = nil;
            }
            else if waiter.prev != nil && waiter.next != nil {
                waiter.prev!.next = waiter.next;
                waiter.next!.prev = waiter.prev;
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
            sendWaiters = new WaiterQue(elt);
            recvWaiters = new WaiterQue(elt);
        }

        proc lock() {
            lock$.writeEF(true);
        }

        proc unlock() {
            lock$.readFE();
        }

        proc recv(out val : eltType, selected = false) : bool {
            if !selected then lock();

            if closed && count == 0 {
                if !selected then unlock();
                return false;
            }

            while !sendWaiters.isEmpty() && sendWaiters.front!.isSelect {
                if !sendWaiters.front!.isSelectDone.deref().testAndSet() {
                    break;
                }
                else sendWaiters.deque();
            }

            if count == 0 && sendWaiters.isEmpty() {
                if selected then return false;
                var process$ : single bool;
                var processing = new unmanaged Waiter(val, process$);
                recvWaiters.enque(processing);
                
                unlock();
                var status = processing.suspend();
                delete processing;
                return status;
            }

            if bufferSize > 0 {
                val = buffer[recvidx];
            }

            if !sendWaiters.isEmpty() {
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
            if !selected then unlock();

            return true;

        }

        proc send(in val : eltType, selected = false) : bool throws {
            if !selected then lock();

            if closed {
                if !selected then unlock();
                throw new owned ChannelError("Sending on a closed channel");
            }

            while !recvWaiters.isEmpty() && recvWaiters.front!.isSelect {
                if !recvWaiters.front!.isSelectDone.deref().testAndSet() {
                    break;
                }
                else recvWaiters.deque();
            }

            if count == bufferSize && recvWaiters.isEmpty() {
                if selected then return false;
                var process$ : single bool;
                var processing = new unmanaged Waiter(val, process$);
                
                sendWaiters.enque(processing);
                unlock();
                var status = processing.suspend();
                delete processing;
                if status == false {
                    throw new owned ChannelError("Sending on a closed channel");
                }
                return status;

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

                if !selected then unlock();
                return true;
            }
        }

        proc close() throws {

            lock();
            if closed {
                unlock();
                throw new owned ChannelError("Closing a closed channel");
            }
            closed = true;
            var queued = new WaiterQue(eltType);
            while(!recvWaiters.isEmpty()) {
                queued.enque(recvWaiters.deque());
            }

            while(!sendWaiters.isEmpty()) {
                queued.enque(sendWaiters.deque());
            }
            unlock();

            while(!queued.isEmpty()) {
                var waiter = queued.deque();
                waiter.release(false);
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

    class BaseClass {
        proc lockChannel() { }
        proc unlockChannel() { }
        proc sendRecv() : bool { return true; }
        proc getAddr() : c_uintptr { return 0 : c_uintptr; }
        proc enqueWaiter(ref process$ : single bool, ref isDone : atomic bool) { }
        proc dequeWaiter() { }
    }

    class SelCase : BaseClass {
        type eltType;
        var val : c_ptr(eltType);
        var channel : chan(eltType);
        var operation : int;
        var waiter : unmanaged Waiter(eltType)?;

        proc init(ref value, ref chan1 : chan(?), oper) {
            eltType = value.type;
            val = c_ptrTo(value);
            channel = chan1.borrow();
            operation = oper;
        }

        override proc lockChannel() {
            channel.lock();
        }

        override proc unlockChannel() {
            channel.unlock();
        }

        override proc sendRecv() : bool {
            if operation == 0 {
                return channel.recv(val.deref(),true);
            }
            else return (try! channel.send(val.deref(), true));
        }

        override proc getAddr() : c_uintptr {
            return ((channel : c_void_ptr) : c_uintptr);
        }

        override proc enqueWaiter(ref process$ : single bool, ref isDone : atomic bool) {
            waiter = new unmanaged Waiter(val, process$, isDone);
            if operation == 0 {
                channel.recvWaiters.enque(waiter!);
            }
            else {
                channel.sendWaiters.enque(waiter!);
            }
        }

        override proc dequeWaiter() {
            if operation == 0 {
                channel.recvWaiters.deque(waiter!);
            }
            else channel.sendWaiters.deque(waiter!);
            delete waiter;
        }
    }

    record Comparator { }

    proc Comparator.compare(case1, case2) {
        return case1.getAddr() - case2.getAddr();
    }

    proc lockSel(lockOrder : list(shared BaseClass)) {
        for channelWrapper in lockOrder do channelWrapper.lockChannel();
    }


    proc unlockSel(lockOrder : list(shared BaseClass)) {
        for idx in lockOrder.indices by -1 do lockOrder[idx].unlockChannel();
    }

    proc selectProcess(cases : [] shared BaseClass, default : bool = false) {
        var numCases = cases.domain.size;

        var addrCmp : Comparator;
        sort(cases, comparator = addrCmp);

        var lockOrder = new list(shared BaseClass);
        for idx in cases.domain {
            if idx == 0 || cases[idx].getAddr() != cases[idx - 1].getAddr() {
                lockOrder.append(cases[idx]);
            }
        }
        var done = false;
        lockSel(lockOrder);

        shuffle(cases);
        for case in cases {
            done = case.sendRecv();
            if done then break;
        }

        if done || default {
            unlockSel(lockOrder);
            return;
        }

        var isDone : atomic bool;
        var process$ : single bool;

        for case in cases {
            cases.enqueWaiter(process$, isDone);
        }

        unlockSel(lockOrder);
        process$.readFF();
        
        lockSel(lockOrder);

        for case in cases {
            case.dequeWaiter();
        }
        unlockSel(lockOrder);
    }
}

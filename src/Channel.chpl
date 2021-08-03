/*
 * Copyright 2020-2021 Hewlett Packard Enterprise Development LP
 * Copyright 2004-2019 Cray Inc.
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
This module contains the implementation of channels which can be used to move
typed data between Chapel tasks.

A channel is a parallel-safe data structure that provides a mechanism for
concurrently executing functions to communicate by sending and receiving values
of a specified element type. A channel can be buffered or unbuffered. A
buffered channel has a maximum capacity specified by ``bufferSize``. There are
mainly three operations that can be performed on the channel.

    * :proc:`send` : Send a value to the channel.
    * :proc:`recv` : Receive a value from the channel.
    * :proc:`close` : Close a channel such that no more value can be sent to it.

The channel operations are blocking, i.e., the calling task will be suspended
if an operation cannot be completed. The channel follows First-In-First-Out
mechanism, i.e., the first value sent to the channel will be received first.
*/

module Channel {

    use CPtr;
    use Sort;
    use SysCTypes;
    use List;
    use Random;

    /*
    A class used to maintain the properties of suspended tasks.
    */
    pragma "no doc"
    class Waiter {
        type valueType;
        var val : c_ptr(valueType);
        var processPtr : c_ptr(single bool);
        var isSelect : bool;
        /* These variables are specific to the waiters for select statement*/
        var isSelectDone : c_ptr(atomic int);
        var selID : int = -1;

        var prev : unmanaged Waiter(valueType)?;
        var next : unmanaged Waiter(valueType)?;

        proc init(ref value, ref process$ : single bool) {
            valueType = value.type;
            val = c_ptrTo(value);
            processPtr = c_ptrTo(process$);
            isSelect = false;
        }

        proc init(ref value, ref process$ : single bool, ref selDone : atomic int, caseID : int) {
            valueType = value.eltType;
            val = value;
            processPtr = c_ptrTo(process$);
            isSelect = true;
            isSelectDone = c_ptrTo(selDone);
            selID = caseID;
        }

        proc suspend() : bool {
            return processPtr.deref().readFF();
        }

        proc release(status : bool) {
            processPtr.deref().writeEF(status);
        }
    }

    /*
    Implementation of doubly-ended queue to keep track of suspended receiving
    and sending tasks.
    */
    pragma "no doc"
    class WaiterQue {
        type eltType;
        var front : unmanaged Waiter(eltType)?;
        var back : unmanaged Waiter(eltType)?;

        /* Push the `waiter` into the queue */
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

        /* Pop the first value from the queue */
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

        /* Remove the specified entry from the queue */
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

        /* The type of elements that can be sent to the channel. */
        type eltType;

        /* Maximum number of elements that the channel can hold at a time. */
        var bufferSize : int;
        pragma "no doc"
        var buffer : [0..#bufferSize] eltType;
        pragma "no doc"
        var sendidx = 0;
        pragma "no doc"
        var recvidx = 0;
        pragma "no doc"
        var count = 0;
        pragma "no doc"
        var closed = false;
        pragma "no doc"
        var sendWaiters : WaiterQue;
        pragma "no doc"
        var recvWaiters : WaiterQue;
        pragma "no doc"
        var lock$ : sync bool;

        /*
        Initialize a channel

        :arg elt: The element type used for sending and receiving
        :type elt: `type`

        :arg size: Specify the maximum capacity for the channel ``bufferSize``.
        :type size: `int`
        */
        proc init(type elt, size = 0) {
            eltType = elt;
            bufferSize = size;
            sendWaiters = new WaiterQue(elt);
            recvWaiters = new WaiterQue(elt);
        }

        pragma "no doc"
        proc lock() {
            lock$.writeEF(true);
        }

        pragma "no doc"
        proc unlock() {
            lock$.readFE();
        }

        /*
        Receive the first value in the channel buffer. It will suspend the
        calling task, until data is sent to the channel. If the channel is
        closed and the buffer is empty, it will return `false` indicating that
        the receive operation was not successful.

        :arg val: Storage for the received value.
        :type val: `eltType`

        :return: `true` if the receive was successful, else `false`.
        :rtype: `bool`
        */

        proc recv(out val : eltType) : bool {
            return recv(val, false);
        }

        pragma "no doc"
        proc recv(out val : eltType, selected : bool) : bool {
            if !selected then lock();

            if closed && count == 0 {
                if !selected then unlock();
                return false;
            }

            while !sendWaiters.isEmpty() && sendWaiters.front!.isSelect {
                if sendWaiters.front!.isSelectDone.deref().compareAndSwap(-1, sendWaiters.front!.selID) {
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

        /*
        Send a value to the channel buffer. If the buffer is at maximum
        capacity it will suspend the waiting task, until there is space in the
        buffer or a receiving task awakes it. If a channel is closed no more
        data can be sent to it.

        :arg val: Data to be sent to the channel
        :type val: `eltType`

        :throws ChannelError: If ``send`` is called on a closed channel.
        */

        proc send(in val : eltType) throws {
            send(val, false);
        }

        pragma "no doc"
        proc send(in val : eltType, selected : bool) : bool throws {
            if !selected then lock();

            if closed {
                if !selected then unlock();
                throw new owned ChannelError("Sending on a closed channel");
            }

            while !recvWaiters.isEmpty() && recvWaiters.front!.isSelect {
                if recvWaiters.front!.isSelectDone.deref().compareAndSwap(-1, recvWaiters.front!.selID) {
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

        /*
        This function is used to close a channel indicating that no more data
        can be sent to it.

        :throws ChannelError: If called on a closed channel.
        */

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

    /* Error class for Channel */
    pragma "no doc"
    class ChannelError : Error {
        var msg:string;

        proc init(msg: string) {
            this.msg = msg;
        }

        override proc message() {
            return msg;
        }
    }

    /* Base class used for aggregating different select-cases */
    pragma "no doc"
    class SelBaseClass {
        proc lockChannel() { }
        proc unlockChannel() { }
        proc getID() : int { return 0; }
        proc sendRecv() : bool { return true; }
        proc getAddr() : c_uintptr { return 0 : c_uintptr; }
        proc enqueWaiter(ref process$ : single bool, ref isDone : atomic int) { }
        proc dequeWaiter() { }
    }

    /* Enum to specify the operation in a select-case */
    pragma "no doc"
    enum selOperation { recv, send }

    pragma "no doc"
    class SelCase : SelBaseClass {
        type eltType;
        var val : c_ptr(eltType);
        var channel : chan(eltType);
        var operation : selOperation;
        var waiter : unmanaged Waiter(eltType)?;
        var id : int;

        proc init(ref value, ref chan1 : chan(?), oper : selOperation, caseID) {
            eltType = value.type;
            val = c_ptrTo(value);
            channel = chan1.borrow();
            operation = oper;
            id = caseID;
        }

        override proc lockChannel() {
            channel.lock();
        }

        override proc unlockChannel() {
            channel.unlock();
        }

        override proc getID() : int {
            return id;
        }

        /* Carry out the case operation and return the status */
        override proc sendRecv() : bool {
            if operation == selOperation.recv {
                return channel.recv(val.deref(),true);
            }
            else return (try! channel.send(val.deref(), true));
        }
        /* Retreive the address of the involved channel */
        override proc getAddr() : c_uintptr {
            return ((channel : c_void_ptr) : c_uintptr);
        }

        override proc enqueWaiter(ref process$ : single bool, ref isDone : atomic int) {
            waiter = new unmanaged Waiter(val, process$, isDone, id);
            if operation == selOperation.recv {
                channel.recvWaiters.enque(waiter!);
            }
            else {
                channel.sendWaiters.enque(waiter!);
            }
        }

        override proc dequeWaiter() {
            if operation == selOperation.recv {
                channel.recvWaiters.deque(waiter!);
            }
            else channel.sendWaiters.deque(waiter!);
            delete waiter;
        }
    }

    /* Comparator used for sorting the channels according to their memory
    addresses.
    */
    pragma "no doc"
    record Comparator { }

    pragma "no doc"
    proc Comparator.compare(case1, case2) {
        return case1.getAddr() - case2.getAddr();
    }

    /* Acquire the lock of all involved channels */
    pragma "no doc"
    proc lockSel(lockOrder : list(shared SelBaseClass)) {
        for channelWrapper in lockOrder do channelWrapper.lockChannel();
    }

    /* Release the lock all involved channels */
    pragma "no doc"
    proc unlockSel(lockOrder : list(shared SelBaseClass)) {
        for idx in lockOrder.indices by -1 do lockOrder[idx].unlockChannel();
    }

    pragma "no doc"
    proc selectProcess(cases : [] shared SelBaseClass, default : bool = false) : int{
        var numCases = cases.domain.size;

        var addrCmp : Comparator;
        // Sort all cases according to their channel adresses
        sort(cases, comparator = addrCmp);

        /*
        Determine the lock order of the involved channels based on their
        addresses. This helps prevent deadlock with other concurrently
        executing select statements
        */
        var lockOrder = new list(shared SelBaseClass);
        for idx in cases.domain {
            if idx == 0 || cases[idx].getAddr() != cases[idx - 1].getAddr() {
                lockOrder.append(cases[idx]);
            }
        }
        var done = -1;
        lockSel(lockOrder);

        /*
        Check all the cases in a random order. This is done to prevent
        starvation on multiple calls to the select statement.
        */
        shuffle(cases);
        for case in cases {
            if case.sendRecv() {
                done = case.getID();
                break;
            }
        }

        if done != -1 || default {
            unlockSel(lockOrder);
            return done;
        }

        /* If none of the channel was ready, enque the select task to each
        channel's waiting queue and wait for other task to awaken us.
        */
        var isDone : atomic int = -1;
        var process$ : single bool;

        for case in cases {
            cases.enqueWaiter(process$, isDone);
        }

        unlockSel(lockOrder);
        process$.readFF();
        
        lockSel(lockOrder);

        /* Deque the waiters from each involved case */
        for case in cases {
            case.dequeWaiter();
        }
        unlockSel(lockOrder);
        return isDone.read();
    }
}

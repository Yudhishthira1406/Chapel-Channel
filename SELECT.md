## Select statement  

This document contains the information about how the compiler would understand
the chapel's `select` statement and convert it to an executable code.

### Data types involved

* `enum SelOperation` : Specify the whether the case is sending or receiving.
* `class SelCase` : It contains information about attributes of a select case like caseID, channel, operation to be done, etc.
* `class SelBaseClass` : Non-generic parent class for `SelCase` to aggregate all cases for implementation purposes.

### Methods Involved
**Method**
```python
proc  SelCase.init(ref value, ref channel : chan(?), op : selOperation, caseID : int)
```
*Arguments*
```
value : Data to be sent or storage for the receiving data.
channel : channel involved for operation.
op : type of operation on the channel.
caseID : ID assigned to the channel by the compiler.
```
**Method**
```python
proc  selectProcess(cases : [] shared SelBaseClass, default : bool = false) : int
```
*Arguments*
```
cases : Array of select cases
default : `true` if a default case is present.
```
Returns
```
int : ID of the successful case, `-1` when default case is executed
```
### An example select statement in Chapel
Note: This syntax is not final, just for understanding purposes.
```python
select {
	when channel1.recv(x1) {
		writeln("Received: ", x1);
	}
	when channel2.send(x2) {
		writeln("Sent: ", x2);
	}
}
```
### Conversion of the above statement into Chapel executable code
* **Step 1:** Wrap the cases with `SelCase` class and type cast it to non-generic `SelBaseClass`
	```python
	var case1 : SelBaseClass = new shared SelCase(x1, channel1, selOperation.recv, 0);
	var case2 : SelBaseClass = new shared SelCase(x2, channel2, selOperation.send, 1);
	```
* **Step 2:** Make a list of all the cases
	```python
	var cases = [case1, case2];
	```
* **Step 3:** Call `proc selectProcess` for the cases.
	```python
	var success = selectProcess(cases, false);
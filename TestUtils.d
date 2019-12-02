module TestUtils;

/** infrastructure useful when 'unittest'ing the DExchange package */

//version(unittest) {

import Types;

import std.stdio;
import std.datetime;
import std.algorithm;
import std.math;
import std.conv;


struct TestResults {
	real total;
	uint numberOfTransactions;

	const bool opEquals(ref const TestResults other)
	{
		// 'numberOfTransactions' is not tested if it is -1
		if (this.numberOfTransactions == -1 || other.numberOfTransactions == -1) {
			return abs(other.total-total) < 1e-6;
		}
		return other.numberOfTransactions == numberOfTransactions &&
			abs(other.total-total) < 1e-6;
	}
}

class TestUtils {

	SysTime testStartTime;
	SysTime subTestStartTime;
	static uint testCount = 0;
	uint subTestsCount;
	uint orderId = 1;

	/** used to test a funcionality, mapped to a product owner requisite */
	void startTest(string requisiteName) {
		writeln(++testCount, ") ",requisiteName,":");
		stdout.flush();
		subTestsCount = 0;
		testStartTime = Clock.currTime();
	}

	/** used to test an indirect functionality/requisite -- usually a low level unfolding of a requisite defined
	by the product owner or a developer/implementation defined behaviour (ultra low level requisite) */
	void startSubTest(string subtest) {
		write("\t",testCount,".",++subTestsCount,") ",subtest,"...");
		stdout.flush();
		subTestStartTime = Clock.currTime();
		//exchange.resetBooks();
	}

	void finishSubTest(bool succeeded = true) {
		if (succeeded) {
			Duration elapsedTime = Clock.currTime() - subTestStartTime;
			writefln(" OK (%,dµs)", elapsedTime.total!"usecs");
		} else {
			writeln(" FAILED:");
		}
		stdout.flush();
	}

	void assertEquals(T)(const T observed, const T expected, string message) {
		import std.traits;
		if (observed != expected) {
			finishSubTest(false);
			writeln("\t\tAssertion Failed: ", message);
			writeln("\t\t\tObserved: ", observed);
			writeln("\t\t\tExpected: ", expected);
			stdout.flush();
			assert(false);
		}
	}

	void finishTest() {
		Duration elapsedTime = Clock.currTime() - testStartTime;
		writefln("\t--> DONE (%d sub-tests in %,dµs)", subTestsCount, elapsedTime.total!"usecs");
		stdout.flush();
	}

}

//}		// version(unittest) {...

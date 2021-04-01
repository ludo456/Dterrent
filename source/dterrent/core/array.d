/**
	Authors: Poggel / Fr3nchK1ss
	Copyright: proprietary / contact dev

	This class is a rewrite of yage3D EngineObject class.
 */

module dterrent.core.array;
import dterrent.system.logger;

import std.format;

/**
 * Add an element to an already sorted array, maintaining the same sort order.
 * replace this with a Heap?
 * Params:
 *     array = The array to use.
 *     value = Value to add.
 *     increasing = The elements are stored in increasing order.
 *     getKey = A function to return a key of type K for each element.
 *     			K must be either a primitive type or a type that impelments opCmp.
 *              Only required for arrays of classes and structs. */
void addSorted(T, K)(ref T[] array, T value, bool increasing,
		K delegate(T elem) getKey, int max_length = int.max)
{
	if (!array.length)
	{
		array ~= value;
		return;
	}

	K key_value = getKey(value);
	if (array.length < max_length) // increase the length
		array.length = array.length + 1; // [below] If fixed length and no place to add, immediately return.
	else if (increasing ? key_value > getKey(array[$ - 1]) : key_value < getKey(array[$ - 1]))
		return;

	// Despite two loops, this still runs in worst-case O(n)
	for (int i = 0; i < array.length - 1; i++) // TODO: Use a binary search instead of linear.
	{
		if (increasing ? key_value <= getKey(array[i]) : key_value >= getKey(array[i]))
		{
			for (int j = array.length - 2; j >= i; j--) // Shift all elements forward
				array[j + 1] = array[j];
			array[i] = value;
			return;
		}
	}

	array[$ - 1] = value;
}

void addSorted(T, K)(ref ArrayBuilder!(T) array, T value, bool increasing,
		K delegate(T elem) getKey, int max_length = int.max) /// ditto
		{
	if (!array.length)
	{
		array ~= value;
		return;
	}

	K key_value = getKey(value);
	if (array.length < max_length) // increase the length
		array.length = array.length + 1; // [below] If fixed length and no place to add, immediately return.
	else if (increasing ? key_value > getKey(array.data[$ - 1]) : key_value < getKey(
			array.data[$ - 1]))
		return;

	// Despite two loops, this still runs in worst-case O(n)
	for (int i = 0; i < array.length - 1; i++) // TODO: Use a binary search instead of linear.
	{
		if (increasing ? key_value <= getKey(array.data[i]) : key_value >= getKey(array.data[i]))
		{
			for (ulong j = array.length - 2; j >= i; j--) // Shift all elements forward
				array.data[j + 1] = array.data[j];
			array.data[i] = value;
			return;
		}
	}

	array.data[$ - 1] = value;
}

bool replaceSmallestIfBigger(T)(T[] array, T item, bool delegate(T a, T b) isABigger)
{
	for (int i = 0; i < array.length; i++)
		if (isABigger(item, array[i]))
		{
			for (int j = i; j < array.length - 1; j++) // move all of the items after it over one place
				array[j + 1] = array[j];
			array[i] = item; // and insert new item
			return true;
		}
	return false;
}

/+
/// Ditto
bool sorted(T, K)(T[] array, bool increasing, K delegate(T elem) getKey)
{
}
unittest
{	assert(sorted([-1, 0, 1, 2, 2, 5]) == true);
	assert(sorted([-1, 0, 1, 2, 1, 5]) == false);
	assert(sorted([5, 3, 3, 3, 2, -1], false) == true);

	import std.algorithm.sorting;
	struct S { int a; }

	S s1; s1.a = 2;
	S s2; s2.a = 3;
	S s3; s3.a = 3;
	S s4; s4.a = 10;

	assert(isSorted([-1, 0, 1, 2, 2, 5]));
	assert(!isSorted([-1, 0, 1, 2, 1, 5]));
	assert(isSorted!"a>b"([5, 3, 3, 3, 2, -1]));

	assert(isSorted!"a.a < b.a"([s1, s2, s3, s4]));
}
+/

/**
 * Remove an element from an array.
 * This takes constant time, or linear time if ordered is true.
 * Params:
 *     array    = The array to use.
 *     index    = Index of the element to remove.
 *     ordered  = Keep all elements in the same order, at the cost of performance. 
 * TODO: this function is broken, see unittest. Kept for backwards compatibility
 */
void remove(T)(ref T[] array, int index, bool ordered = true)
{
	if (ordered)
		for (size_t i = index; i < array.length - 1; i++)
			array[i] = array[i + 1];
	else if (index != array.length - 1)
				array[index] = array[array.length - 1];
	array.length = array.length - 1;
}

unittest
{
	// Remove
	int[] test1 = [0, 1, 2, 3, 4];
	test1.remove(0);
	test1.remove(4); // BROKEN, should fail! index 4 does not exist any more...
	assert(test1 == [1, 2, 3]);
	test1.remove(0, false);
	assert(test1 == [3, 2]);

	import m = std.algorithm.mutation : remove;

	alias mmove = m.remove;
	int[] test2 = [0, 1, 2, 3, 4];

	test2 = mmove(test2, 0);
	test2 = mmove(test2, 3);
	assert(test2 == [1, 2, 3]);
}

/**
 * Sort the elements of an array using a radix sort.
 * This runs in linear time and can sort several million items per second on modern hardware.
 * Special thanks go to Pierre Terdiman for his essay: Radix Sort Revisited.
 * Params:
 *     getKey = A function to return a key of type K for each element.
 *              Only required for arrays of classes and structs.
 *     signed = interpret the key data as being signed.  Defaults to true.
 * Example:
 * --------------------------------
 * Timer[] array;
 * // ... fill array with new Timer() ...
 * array.radixSort((Timer a) { return a.tell(); }); // sort timers by thier time
 * --------------------------------
 */
void radixSort(T)(T[] array, bool increasing = true)
{
	radixSort(array, increasing, (T a) { return a; });
}

/// ditto
void radixSort(T, K)(T[] array, bool increasing, K delegate(T elem) getKey, bool signed = true)
{ // Are we sorting floats?
	bool isfloat = false;
	static if (is(K == float) || is(K == double) || is(K == real)
			|| is(K == ifloat) || is(K == idouble) || is(K == ireal)
			|| // Not sure if these will work.
			 is(K == cfloat) || is(K == cdouble) || is(K == creal))
		isfloat = true;

	// A struct to hold our key and a pointer to our value
	struct Elem
	{
		union
		{
			K key2; // The sort key is of variable size
			byte[K.sizeof] key;
		}

		T data;
	}

	// Perform the radix sort.
	ulong count = array.length;
	Elem[] elem = new Elem[count];
	Elem[] elem_copy = new Elem[count];

	// Move everything into an array of structs for faster sorting.
	// This way we don't get all of the cache misses from using classes by reference.
	for (size_t i = 0; i < count; i++)
	{
		elem[i].key2 = getKey(array[i]);
		elem[i].data = array[i];
	}

	for (int k = 0; k < K.sizeof; k++)
	{
		// Build histograms
		uint[256] histogram;
		for (size_t i = 0; i < count; i++)
			histogram[cast(ubyte) elem[i].key[k]]++;

		// Count negative values
		uint neg;
		bool last_pass = k == K.sizeof - 1;
		if (signed && last_pass)
			for (size_t i = 128; i < 256; i++)
				neg += histogram[i];

		// Build offset table
		uint[256] offset;
		offset[0] = neg;
		for (int i = 0; i < 127; i++)
			offset[i + 1] = offset[i] + histogram[i];
		if (neg) // only if last past and negative
			offset[128] = 0;
		else
			offset[128] = offset[127] + histogram[127];
		for (int i = 128; i < 255; i++)
			offset[i + 1] = offset[i] + histogram[i];

		// Fill destination buffer
		if (!isfloat || !last_pass || !neg) // sort as usual
			for (size_t i = 0; i < count; i++)
				elem_copy[offset[cast(ubyte) elem[i].key[k]]++] = elem[i];
		else // special case if floating point negative numbers exist
		{
				int negm1 = neg - 1;
				for (size_t i = 0; i < count; i++)
				{
					int value = elem[i].key[k];
					int index = offset[cast(ubyte) value]++;
					if (value >= 0)
						elem_copy[index] = elem[i];
					else // put all negative numbers in reverse order, since not represented /w 2's comp
						elem_copy[negm1 - index] = elem[i];
				}
			}

		// Only not swap arrays if last pass of an odd size (rare).
		if (!last_pass || K.sizeof % 2 == 0)
		{
			Elem[] temp = elem_copy;
			elem_copy = elem;
			elem = temp;
		}
	}

	// Move everything back again
	// If odd number of passes, move data back to return buffer
	if (increasing)
	{
		static if (K.sizeof % 2 == 1)
			for (size_t i = 0; i < count; i++)
				array[i] = elem_copy[i].data;
		else
			for (size_t i = 0; i < count; i++)
				array[i] = elem[i].data;
	}
	else
	{
		static if (K.sizeof % 2 == 1)
			for (size_t i = 0; i < count; i++)
				array[count - i - 1] = elem_copy[i].data;
		else
			for (size_t i = 0; i < count; i++)
				array[count - i - 1] = elem[i].data;
	}
}

unittest
{
	// Sort ints
	int[] test2 = [3, 5, 2, 0, -1, 7, -4];
	test2.radixSort();
	assert(test2 == [-4, -1, 0, 2, 3, 5, 7]);
	test2.radixSort(false);
	assert(test2 == [7, 5, 3, 2, 0, -1, -4]);

	// Sort doubles
	double[] test3 = [3.0, 5, 2, 0, -1, 7, -4];
	test3.radixSort();
	assert(test3 == [-4.0, -1, 0, 2, 3, 5, 7]);

	// large array of +- floats
	import std.random;

	float[] test4;
	for (int i = 0; i < 10000; i++)
		test4 ~= choice([-1000, 1000]);
	test4.radixSort();
	import std.algorithm.sorting;

	assert(test4.isSorted);
}

/**
 * Behaves the same as built-in arrays, except about 6x faster with concatenation at the expense of the base pointer
 * being 4 system words instead of two (16 instead of 8 bytes on a 32-bit system).
 * Internally, it's implemented similarly to java's StringBuffer.
 * Use .data to access the underlying array.
 * ArrayBuilder is a value type, so all copies point to the same data, unless either:
 * - A slice is taken and then appended to.
 * - .dup() is called. */
struct ArrayBuilder(T)
{
	alias ArrayBuilder!(T) AT;

	private T[] array; // array.length is capacity
	private size_t size; // current used size
	size_t reserve; // capacity will never be less than this size, takes effect after the next grow.

	///
	static AT opCall()
	{
		AT result;
		return result;
	}

	///
	static AT opCall(T[] elems)
	{
		AT result;
		result.array = elems;
		result.size = elems.length;
		return result;
	}

	///
	size_t capacity()
	{
		return array.length;
	}

	///
	T[] data()
	{
		return array[0 .. size];
	}

	///
	void dispose()
	{
		array.destroy();
	}

	///
	AT dup()
	{
		AT result;
		result.array = array.dup;
		result.size = size;
		return result;
	}

	///
	size_t length()
	{
		return size;
	}

	///
	void length(size_t l)
	{
		size = l;
		grow();
	}

	///
	int opApply(int delegate(ref T) dg)
	{
		int result = 0;
		for (int i = 0; i < size; i++)
		{
			result = dg(array[i]);
			if (result)
				break;
		}
		return result;
	}

	///
	AT opAssign(T[] elem)
	{
		array = elem;
		size = elem.length;
		return this;
	}

	///
	AT opCat(T elem)
	{
		return AT(array ~ elem);
	}

	AT opCat(T[] elem) /// ditto
	{
		return AT(array ~ elem);
	}

	AT opCat(AT elem) /// ditto
	{
		return AT(array ~ elem.array);
	}

	///
	void opOpAssign(string op)(T elem) if (op == "~")
	{
		size++;
		grow();
		array[size - 1] = elem;
	}

	/// temporary until opCatAssign always works
	T* append(T elem)
	{
		size++;
		grow();
		array[size - 1] = elem;
		return &array[size - 1];
	}

	void opCatAssign(T[] elem) /// ditto
	{
		size_t old_size = size; // same as push
		size += elem.length;
		grow();
		array[old_size .. size] = elem[0 .. $];
	}

	void opOpAssign(string op)(AT elem) if (op == "~")
	{
		size_t old_size = size;
		size += elem.array.length;
		grow();
		array[old_size .. size] = elem.array[0 .. $];
	}

	/// TODO: This returns a copy, so a[i].b = 3; doesn't work!!
	T* opIndex(size_t i)
	{
		assert(i < size, format("array index %s out of bounds 0..%s", i, size));
		return &array[i];
	}

	T opIndexAssign(T val, size_t i) /// ditto
	{
		assert(i < size, format("array index %s out of bounds 0..%s", i, size));
		return array[i] = val;
	}

	///
	AT opSlice() // overloads a[], a slice of the entire array
	{
		return AT(array[0 .. size]);
	}

	AT opSlice(size_t start, size_t end) /// ditto
	{
		assert(end <= size, format("array index %s out of bounds 0..%s", end, size));
		return AT(array[start .. end]); // overloads a[i .. j]
	}

	///
	AT opSliceAssign(T v) // overloads a[] = v
	{
		array[0 .. size] = v;
		return this;
	}

	///
	AT opSliceAssign(T v, size_t start, size_t end) // overloads a[i .. j] = v
	{
		assert(end <= size);
		array[start .. end] = v;
		return this;
	}

	void reserveAndClear()
	{
		if (reserve < array.length)
			reserve = array.length;
		size = 0;
	}

	///
	T* ptr()
	{
		return array.ptr;
	}

	/// Remove an element, replacing it with one from the end.
	void remove(size_t index)
	{
		array[index] = array[size - 1];
		size--;
	}

	///
	import std.algorithm.mutation;

	AT reverse()
	{ //array.reverse;
		array.reverse;
		return this;
	}

	/**
	 * Add and remove elements from the array, in-place.
	 * Params:
	 *     index =
	 *     remove = Number of elements to remove, including and after index (can be 0)
	 *     insert = Element to insert before index, after elements have been removed. */
	void splice(size_t index, size_t remove, T[] insert...)
	{
		// Split member 'array' in two parts
		T[] firstPart = array[0 .. index];
		T[] secondPart = array[index + remove .. $];
		length(firstPart.length + insert.length + secondPart.length);

		array = firstPart ~ insert ~ secondPart;
	}

	///
	string toString() const
	{
		return ""; // TODO this needs to output the data. swritef(data);
	}

	private void grow()
	{
		if (array.length < size || size * 4 < array.length)
		{
			ulong new_size = size * 2 + 1;
			if (new_size < reserve)
				new_size = reserve;
			array.length = new_size;
		}
	}
}

unittest
{
	{
		struct A
		{
			int x, y;
		}

		A a;
		ArrayBuilder!(A) array;
		array ~= a;
		array[0].x = 3;
		assert(array[0].x == 3);
	}
	{ // Test slice and append; ensure copy on append is performed
		immutable test = ArrayBuilder!(int)([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		auto original = ArrayBuilder!(int)([0, 1, 2, 3]);
		auto s = original[1 .. 3];
		assert(s[0] == original[1]); // compares pointer
		s ~= 12;
		assert(*s[0] == 1);
		assert(*s[1] == 2);
		assert(*s[2] == 12);
		assert(*original[3] == 3);
	}
	{ // Test splice
		auto test = ArrayBuilder!(int)([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		test.splice(3, 3);
		assert(test.data == [0, 1, 2, 6, 7, 8, 9]);
		test.splice(3, 0, [3, 4, 5]);
		assert(test.data == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		test.splice(0, 3, [2, 1, 0]);
		assert(test.data == [2, 1, 0, 3, 4, 5, 6, 7, 8, 9]);
		test.splice(test.length, 0, 10);
		assert(test.data == [2, 1, 0, 3, 4, 5, 6, 7, 8, 9, 10]);

		auto test2 = ArrayBuilder!(int)();
		test2.splice(0, 0, 1);
		assert(test2.data == [1]);
	}
	{
		trace("*** ArrayBuilder benchmark ***");
		import std.datetime.stopwatch : benchmark, Duration;
		import std.array : appender;

		void concat_withstd()
		{
			int[] array;
			for (int j = 0; j < 1000; j++)
				array ~= j;
		}

		void concat_withArrayBuilder()
		{
			ArrayBuilder!(int) array;
			for (int j = 0; j < 1000; j++)
				array ~= j;
		}

		void concat_withReserve()
		{
			int[] array;
			array.reserve(1000);
			for (int j = 0; j < 1000; j++)
				array ~= j;
		}

		void concat_withLength()
		{
			int[] array;
			array.length = 1000;
			for (int j = 0; j < 1000; j++)
				array[j] = j;
		}

		void concat_withAppender()
		{
			auto array = appender!(int[]);
			//trace ("array is ", array);
			array.reserve(1000);
			for (int j = 0; j < 1000; j++)
				array ~= j;
		}

		auto r = benchmark!(concat_withstd, concat_withArrayBuilder,
				concat_withReserve, concat_withLength, concat_withAppender)(1000);
		Duration bench1 = r[0];
		Duration bench2 = r[1];
		Duration bench3 = r[2];
		Duration bench4 = r[3];
		Duration bench5 = r[4];

		tracef("Concatenation with std: %s", bench1);
		tracef("Concatenation with Arraybuilder: %s", bench2);
		tracef("Concatenation with Reserve: %s", bench3);
		tracef("Concatenation with Length: %s", bench4);
		tracef("Concatenation with Appender: %s \n", bench5);

	}
}

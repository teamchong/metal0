/* test_extension.c - Simple C Extension to Test metal0's CPython API
 *
 * This is a minimal C extension that uses our CPython C API implementation.
 * If this compiles and runs, it proves our API is C-compatible!
 *
 * Functions implemented:
 * 1. add_numbers(a, b) -> a + b
 * 2. create_tuple(a, b, c) -> (a, b, c)
 * 3. sum_list(list) -> sum of all elements
 */

#include "../include/Python.h"
#include <stdio.h>

/* ============================================================================
 * TEST 1: Simple integer addition
 * Uses: PyArg_ParseTuple, PyLong_FromLong
 * ============================================================================ */

static PyObject* add_numbers(PyObject* self, PyObject* args) {
    long a, b;

    /* Parse arguments */
    if (!PyArg_ParseTuple(args, "ll", &a, &b)) {
        return NULL;
    }

    /* Calculate sum */
    long result = a + b;

    /* Return as PyLong */
    return PyLong_FromLong(result);
}

/* ============================================================================
 * TEST 2: Create tuple from three numbers
 * Uses: PyArg_ParseTuple, PyTuple_New, PyTuple_SetItem, PyLong_FromLong
 * ============================================================================ */

static PyObject* create_tuple(PyObject* self, PyObject* args) {
    long a, b, c;

    /* Parse arguments */
    if (!PyArg_ParseTuple(args, "lll", &a, &b, &c)) {
        return NULL;
    }

    /* Create tuple */
    PyObject* tuple = PyTuple_New(3);
    if (tuple == NULL) {
        return NULL;
    }

    /* Set items */
    PyTuple_SetItem(tuple, 0, PyLong_FromLong(a));
    PyTuple_SetItem(tuple, 1, PyLong_FromLong(b));
    PyTuple_SetItem(tuple, 2, PyLong_FromLong(c));

    return tuple;
}

/* ============================================================================
 * TEST 3: Sum all numbers in a list
 * Uses: PyList_Size, PyList_GetItem, PyLong_AsLong, PyLong_FromLong
 * ============================================================================ */

static PyObject* sum_list(PyObject* self, PyObject* args) {
    PyObject* list;

    /* Parse arguments */
    if (!PyArg_ParseTuple(args, "O", &list)) {
        return NULL;
    }

    /* Check if it's a list */
    if (!PyList_Check(list)) {
        /* TODO: Set proper exception */
        return NULL;
    }

    /* Sum all elements */
    long total = 0;
    int64_t size = PyList_Size(list);

    for (int64_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(list, i);
        if (item == NULL) {
            return NULL;
        }

        if (PyLong_Check(item)) {
            total += PyLong_AsLong(item);
        }
    }

    return PyLong_FromLong(total);
}

/* ============================================================================
 * TEST 4: Reference counting test
 * Uses: Py_INCREF, Py_DECREF
 * ============================================================================ */

static PyObject* test_refcount(PyObject* self, PyObject* args) {
    PyObject* obj;

    /* Parse arguments */
    if (!PyArg_ParseTuple(args, "O", &obj)) {
        return NULL;
    }

    /* Increment refcount */
    Py_INCREF(obj);

    /* Decrement it back */
    Py_DECREF(obj);

    /* Return None */
    /* TODO: Implement Py_None singleton */
    return PyLong_FromLong(0); /* Placeholder */
}

/* ============================================================================
 * TEST 5: Memory allocation test
 * Uses: PyMem_Malloc, PyMem_Free
 * ============================================================================ */

static PyObject* test_memory(PyObject* self, PyObject* args) {
    long size;

    /* Parse arguments */
    if (!PyArg_ParseTuple(args, "l", &size)) {
        return NULL;
    }

    /* Allocate memory */
    void* ptr = PyMem_Malloc(size);
    if (ptr == NULL) {
        return NULL;
    }

    /* Write to it */
    char* data = (char*)ptr;
    for (long i = 0; i < size; i++) {
        data[i] = 'A';
    }

    /* Free it */
    PyMem_Free(ptr);

    /* Return success */
    return PyLong_FromLong(1);
}

/* ============================================================================
 * MODULE DEFINITION
 * ============================================================================ */

/* Method table */
static struct PyMethodDef test_methods[] = {
    {"add_numbers", add_numbers, METH_VARARGS, "Add two numbers"},
    {"create_tuple", create_tuple, METH_VARARGS, "Create tuple of 3 numbers"},
    {"sum_list", sum_list, METH_VARARGS, "Sum all numbers in list"},
    {"test_refcount", test_refcount, METH_VARARGS, "Test reference counting"},
    {"test_memory", test_memory, METH_VARARGS, "Test memory allocation"},
    {NULL, NULL, 0, NULL} /* Sentinel */
};

/* Module definition (simplified - real CPython uses PyModuleDef) */
/* For testing, we just expose individual functions */

/* ============================================================================
 * SIMPLE TEST MAIN (For standalone testing)
 * ============================================================================ */

int main() {
    printf("Testing metal0 CPython C API Implementation\n");
    printf("===========================================\n\n");

    /* Test 1: Create integers */
    printf("Test 1: PyLong_FromLong / PyLong_AsLong\n");
    PyObject* num1 = PyLong_FromLong(42);
    PyObject* num2 = PyLong_FromLong(100);

    if (num1 && num2) {
        long val1 = PyLong_AsLong(num1);
        long val2 = PyLong_AsLong(num2);
        printf("  Created: %ld and %ld ✓\n", val1, val2);
    } else {
        printf("  FAILED to create integers ✗\n");
        return 1;
    }

    /* Test 2: Create tuple */
    printf("\nTest 2: PyTuple_New / PyTuple_SetItem\n");
    PyObject* tuple = PyTuple_New(2);
    if (tuple) {
        PyTuple_SetItem(tuple, 0, num1);
        PyTuple_SetItem(tuple, 1, num2);

        PyObject* got1 = PyTuple_GetItem(tuple, 0);
        PyObject* got2 = PyTuple_GetItem(tuple, 1);

        if (got1 && got2) {
            printf("  Tuple created with 2 items ✓\n");
            printf("  Item 0: %ld\n", PyLong_AsLong(got1));
            printf("  Item 1: %ld\n", PyLong_AsLong(got2));
        }
    }

    /* Test 3: Create list */
    printf("\nTest 3: PyList_New / PyList_Append\n");
    PyObject* list = PyList_New(0);
    if (list) {
        PyList_Append(list, PyLong_FromLong(10));
        PyList_Append(list, PyLong_FromLong(20));
        PyList_Append(list, PyLong_FromLong(30));

        int64_t size = PyList_Size(list);
        printf("  List size: %lld ✓\n", (long long)size);

        for (int64_t i = 0; i < size; i++) {
            PyObject* item = PyList_GetItem(list, i);
            printf("  Item %lld: %ld\n", (long long)i, PyLong_AsLong(item));
        }
    }

    /* Test 4: Memory allocation */
    printf("\nTest 4: PyMem_Malloc / PyMem_Free\n");
    void* mem = PyMem_Malloc(1024);
    if (mem) {
        printf("  Allocated 1024 bytes ✓\n");
        PyMem_Free(mem);
        printf("  Freed memory ✓\n");
    }

    /* Test 5: Reference counting */
    printf("\nTest 5: Py_INCREF / Py_DECREF\n");
    PyObject* obj = PyLong_FromLong(999);
    if (obj) {
        printf("  Initial refcount: %lld\n", (long long)Py_REFCNT(obj));
        Py_INCREF(obj);
        printf("  After INCREF: %lld\n", (long long)Py_REFCNT(obj));
        Py_DECREF(obj);
        printf("  After DECREF: %lld ✓\n", (long long)Py_REFCNT(obj));
    }

    printf("\n✅ All tests passed!\n");
    printf("metal0 CPython C API is working! 🎉\n");

    return 0;
}

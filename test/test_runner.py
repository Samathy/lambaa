#!/usr/bin/env python
from pprint import pp
from subprocess import check_call, Popen
import json
import os
import pathlib
import requests
from contextlib import contextmanager
from time import sleep

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def lambaa():
    return Popen("./lambaa", cwd="../") # We should check that it runs okay, actually.

@contextmanager
def test_setup(f, fname):
    try:
        check_call(["cp", f, "../scripts/"+fname])
        yield
    finally:
        print("Would remove "+"../scripts/"+fname)
#        check_call(["rm", "../scripts/"+fname])

@contextmanager
def lambaa_setup():
    pid = None
    try:
        pid = lambaa()
        yield
    finally:
        pid.kill()



def run_test(test):
    """ Make the request """
    print(bcolors.HEADER + "Running test: "+ test + bcolors.ENDC)
    results = dict()
    with open(pathlib.Path(test,"test.ini"), "r") as testini:
        testini_json = json.loads(testini.read())

        expected_result = (testini_json["result"],testini_json["body"])

        with test_setup(pathlib.Path(test,testini_json["file_name"]), testini_json["file_name"]):

            r = requests.get("http://127.0.0.1:8080/"+testini_json["test_name"])

            print("Status Code:" + str(r.status_code))
            print("Body:" + r.text)
            print("Expected Status code: "+ str(expected_result[0]))
            print("Expected text: "+ expected_result[1])
            try:
                assert r.status_code == expected_result[0]
                assert r.text == expected_result[1]
                results[testini_json["file_name"]] = "PASSED"
            except AssertionError:
                print ( "Test: " + bcolors.BOLD + test + bcolors.ENDC + " " + bcolors.FAIL + "FAILED" + bcolors.ENDC )
                results[testini_json["file_name"]] = "FAILED"

    print ( "Test: " + bcolors.BOLD + test + bcolors.ENDC + " " + bcolors.OKGREEN + "PASSED" + bcolors.ENDC    )
    return results

def print_results(results):
    pp(results)
    
    
def execute_tests():
    test_directories = os.listdir(".")
    results = dict()
    with lambaa_setup():
        sleep(2)
        for test in test_directories:
            if test == "test_runner.py":
                break
            results[test] = run_test(test)
    print("\n\n")
    pp(results)


if __name__ == "__main__":
    execute_tests()

## Bash Script Testing wuth BATS (Bash Automated Testing System)

*This breakdown was written by Tim Perry and you can find this tutorial in his Medium [article here](https://medium.com/@pimterry/testing-your-shell-scripts-with-bats-abfca9bdc5b9).*

Writing tests for Bash can be challenging, since there is no built-in object support, there are only two type definitions (int and string), and thus no built-in hierachy definitions. That isn't a knock on bash or shell scripts, because at the end of the day, Bash and all shells are Operating Systems and not programming languages. Nevertheless, I'm including this handy tutorial in the README section of the unit-test folders in all of my projects going forward so it will always be on-hand when I need it to automate script tests.

The BATS GithUb repo can be found [here](https://github.com/sstephenson/bats).

### Setting up a test environment
Bats is the core testing library, Bats-Assert adds lots of extra asserts for more readable tests, and Bats-Support adds some better output formatting (and is a prerequisite for Bats-Assert).

To pull all these submodules into test/libs, run the below from the root of your git repo and commit the result:
```bash
mkdir -p test/libs

git submodule add https://github.com/sstephenson/bats test/libs/bats
git submodule add https://github.com/ztombol/bats-support test/libs/bats-support
git submodule add https://github.com/ztombol/bats-assert test/libs/bats-assert
```
You might want to run a quick test file to try it out:
```bash

#!./test/libs/bats/bin/bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Should add numbers together" {
    assert_equal $(echo 1+1 | bc) 2
}
```

Line by line description of test above

* A shebang that loads the bats executable relatively, from the libs submodule we’ve included, so that if you `chmod +x test/test.bats` and run this file directly it’ll run itself with bats.
* `load 'file'` — this is a Bats command to let you easily load files, here the load.sh scripts that initialise both Bats-Support and Bats-Assert.
* A `@test` call, which defines a test, with a name and a body. Bats will run this test for us, and it passes if every single line within it returns a zero status code.
* A call to `assert_equal`, checking that the output of `echo 1+1 | bc` is 2.

You can run this with `./test/libs/bats/bin/bats test/*.bats`.

That’s a bit of a mouthful though, so you’ll normally want a more convenient way to run these. Ideally, you would want to have two scripts, one (test.sh) in the root of the project, which runs the tests a single time for a quick check and for CI, and one (dev.sh) which watches my files and reruns the tests whenever they change, for quick development feedback.
#### test.sh
```bash
# Run this file to run all the tests, once
./test/libs/bats/bin/bats test/*.bats
```

#### dev.sh
```bash
# Run this file (with 'entr' installed) to watch all files and rerun tests on changes
ls -d **/* | entr ./test.sh
```

`chmod +x` both of these, and you’re away. Contributors can now check out your project and run the tests with just:
```bash
git clone <your repo>
git submodule update --init --recursive
./test.sh
```

### Writing your own tests
Once you have this set up, writing tests for Bats is pretty easy: work out what you’d run on the command line to check your program works, write exactly that wrapped with a `@test` call and a name, and Bats will do the rest.

Checking the results of each step can be slightly tricky, since you can’t just eyeball command output, but the key is to remember that any failing line is a failing test. You can just write any bash conditional by itself on a line to define an assert, e.g. `[ -f "$file" ] ($file exists)` or `[ -z "$result" ]` ($result is empty).

You’ll also often want test setup and teardown steps to run before and after each of your tests, to manage their environment. Bats makes this incredibly easy: define functions called `setup` and `teardown`, and they’ll be automatically run before and after each test execution.

In many cases, you’ll want to run a command and assert on its resulting status and output, rather than immediately failing if it returns non-zero. Bats provides a `run` function to make this easier, which wraps commands to return non-zero, and puts the command result into `$status` and `$output` variables. Bats-Assert then provides a nice selection of nice assertion functions to easily check these. Here’s an example from notes:
#### notes-find-test.sh
```bash
@test "Should show matching notes only if a pattern is provided to find" {
  touch $NOTES_DIRECTORY/match-note1.md
  touch $NOTES_DIRECTORY/hide-note2.md

  run $notes find "match"

  assert_success
  assert_line "match-note1.md"
  refute_line "hide-note2.md"
}
```
You can take a closer look at the real test in action [here](https://github.com/pimterry/notes/blob/5a6eb9c/test/test-find.bats#L43-L52).

There’s lots of more specific techniques to look at here, from mocking to test helpers to test isolation practices, but this should be more than enough to get you started, so you can verify your shell scripts work, and quickly tell whether future changes and PRs break anything. If you want more examples, take a look at the set of test included in [notes](https://github.com/pimterry/notes/tree/master/test) and [git-confirm](https://github.com/pimterry/git-confirm/tree/master/test), both of which cover some more interesting practices here.

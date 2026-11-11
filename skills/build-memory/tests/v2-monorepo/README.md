# monorepo fixture

A monorepo whose build memory lives in a subproject (`sub/proj/docs/{build,tickets,adr}`), selected with
`BUILD_MEMORY_ROOT=sub/proj/docs/build`. Used by `run-tests.sh` `test_monorepo`.

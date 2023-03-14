# map reduce

## Todo list

### General

- [x] local evaluation process worked
- [x] distributed evaluation process worked
- [] use redis as store

### Server

- [x] handle single workers
- [x] handle multiple workers
- [x] exit gracefully informing the workers(now through invalid context)
- [x] handle failure in workers
- [x] timeout if worker is taking too long

### Worker

- [x] exit gracefully(now through invalid context received from server)

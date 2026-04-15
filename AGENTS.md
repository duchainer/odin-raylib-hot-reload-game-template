# Project Notes
## Odin Memory Behavior
- Odin zeroes memory by default for struct allocations (`new(T)`, `make(T)`, struct literals with `{}`).
- Only when we use `= ---` are we explicitely not zero-ing
- This means padding bytes in structs are zeroed, so hashing raw struct bytes is safe — no need for field-by-field hashing to avoid padding garbage.


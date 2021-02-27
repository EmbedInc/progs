/*   Messages from the PROGS library.
/*

/*   GET_NEWER program.
/*
msg gnew_circ
  lan english -def
    ERROR: Destination is within source tree.
msg gnew_currdir
  lan english -def
    On attempt to get current working directory pathname.
msg gnew_snexist
  lan english -def
    Source "%p1s" not found.
msg gnew_nsource
  lan english -def
    No source tree specified.
msg gnew_same
  lan english -def
    ERROR: Source and destination "%p1s" are the same.
msg gnew_start
  lan english -def
    .nfill
    Updating %p2s <-- %p1s

/*   MPMEM program.
/*
msg mpmem_eof
  lan english -def
    Unexpected end of file encountered.  File %p1s" is not a valid MPLINK
    map file.
msg mpmem_err_atline
  lan english -def
    On reading line %p1i of file "%p2s".
msg mpmem_tk_eol
  lan english -def
    Unexpected end of line %p1i encountered in file "%p2s".
msg mpmem_tkint_err
  lan english -def
    Token "%p1s" on line %p2i of file "%p3s" is not a valid integer.

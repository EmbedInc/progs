{   Program PLOTFILT option ... option
*
*   Plot the step response and other responses of a series of filters.  See the
*   doc file for details.
}
program plotfilt;
%include 'base.ins.pas';
%include 'math.ins.pas';
%include 'stuff.ins.pas';

const
  thresh_def = 0.999;                  {default unit step convergence threshold}
  max_msg_args = 1;                    {max arguments we can pass to a message}

type
  pole_p_t = ^pole_t;
  pole_t = record                      {state for one filter pole}
    ff: double;                        {filter fraction}
    step: double;                      {unit step input}
    impl: double;                      {unit impulse input}
    rand: double;                      {random noise input}
    next_p: pole_p_t;                  {points to next pole in filter, NIL for last}
    end;

  stepth_p_t = ^stepth_t;
  stepth_t = record                    {info about one step response threshold}
    th: real;                          {the threshold 0.0 to 1.0}
    iter: sys_int_machine_t;           {first iteration at or past the threshold}
    iterf: real;                       {interpolated iteration for the exact threshold}
    next_p: stepth_p_t;                {pointer to next threshold in the list}
    found: boolean;                    {this threshold was found}
    end;

var
  filt_p: pole_p_t;                    {points to the chain of filter poles}
  last_p: pole_p_t;                    {points to last pole in chain}
  npoles: sys_int_machine_t;           {number of poles in the filter}
  stepth_list_p: stepth_p_t;           {points to list of step response thresholds}
  enditer: sys_int_machine_t;          {end iteration, 0 for use step convergence}
  endstep: double;                     {end when step gets to this value, 0.0 for none}
  tstep: double;                       {seconds per filter iteration, 0 = use iter for X axis}
  rand: math_rand_seed_t;              {random number generator state}
  name:                                {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  mem_p: util_mem_context_p_t;         {points to our top level memory context}
  plot: boolean;                       {plot CSV file result}

  csv: csv_out_t;                      {CSV file writing state}
  pole_p: pole_p_t;                    {scratch pointer to a filter pole}
  r: double;                           {scratch floating point}
  ii: sys_int_machine_t;               {scratch integer}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Subroutine STEPTH_ADD (TH)
*
*   Add the threshold TH to the list of step response thresholds.  The list of
*   response thresholds is kept sorted in low to high order.  The new list entry
*   is added before the first entry that is greater than or equal to the new
*   entry.
}
procedure stepth_add (                 {add entry to step response thresholds list}
  in      th: real);                   {threshold to add}
  val_param; internal;

var
  sth_p: stepth_p_t;                   {pointer to new threshold descriptor}
  curr_p: stepth_p_t;                  {pointer to current list entry}
  prev_p: stepth_p_t;                  {pointer to previous list entry}

begin
  util_mem_grab (                      {allocate memory for the new descriptor}
    sizeof(sth_p^),                    {amount of memory to allocate}
    mem_p^,                            {parent memory context}
    false,                             {won't need to individually deallocate}
    sth_p);                            {returned pointer to the new memory}

  sth_p^.th := max(0.0, min(1.0, th)); {save the threshold value}
  sth_p^.iter := 0;                    {init to benign values}
  sth_p^.iterf := 0.0;
  sth_p^.found := false;               {init to this threshold not found yet}

  if stepth_list_p = nil then begin    {there is no previous list ?}
    sth_p^.next_p := nil;              {indicate no list entry after this one}
    stepth_list_p := sth_p;            {this is now first list entry}
    return;
    end;

  prev_p := nil;                       {init to no previous list entry}
  curr_p := stepth_list_p;             {init to first list entry}
  while curr_p <> nil do begin         {scan the list entries}
    if sth_p^.th <= curr_p^.th then begin {insert before this entry ?}
      sth_p^.next_p := curr_p;         {new entry points on to current entry}
      if prev_p = nil
        then begin                     {insert at start of list}
          stepth_list_p := sth_p;      {update start of list pointer}
          end
        else begin                     {insert after previous entry}
          prev_p^.next_p := sth_p;     {previous entry points on to new entry}
          end
        ;
      return;                          {done updating list}
      end;
    prev_p := curr_p;                  {advance to the next list entry}
    curr_p := curr_p^.next_p;
    end;                               {back to process this new current entry}
{
*   The new entry has a value larger than any previous list entry.  Add it the
*   new entry to the end of the list.  PREV_P is pointing to the last list
*   entry.
}
  sth_p^.next_p := nil;                {new entry has no entry following it}
  prev_p^.next_p := sth_p;             {point last entry to the new entry}
  end;
{
********************************************************************************
*
*   Subroutine SHOW_THRESH
*
*   Show the time or iteration of any step response thresholds that were found.
}
procedure show_thresh;
  val_param; internal;

var
  th_p: stepth_p_t;                    {pointer to current thresholds list entry}
  tk: string_var32_t;                  {scratch token}

begin
  tk.max := size_char(tk.str);         {init local var string}

  th_p := stepth_list_p;               {init to first thresholds list entry}
  while th_p <> nil do begin           {scan the list}
    if not th_p^.found then return;    {all further thresholds not found ?}
    string_f_fp_free (tk, th_p^.th, 3);
    write ('Step response of ', tk.str:tk.len, ' at ');
    if tstep = 0
      then begin                       {X axis is iteration}
        string_f_fp_fixed (tk, th_p^.iterf, 2);
        writeln (tk.str:tk.len, ' iterations');
        end
      else begin                       {X axis is seconds}
        string_f_fp_free (tk, th_p^.iterf * tstep, 5);
        writeln (tk.str:tk.len, ' seconds');
        end
      ;
    th_p := th_p^.next_p;              {advance to next list entry}
    end;                               {back to do this next list entry}
  end;
{
********************************************************************************
*
*   Subroutine WRITE_ITERATION (ITER, STAT)
*
*   Write the current filters result to the CSV file.  The filters state is the
*   result of iteration ITER.
}
procedure write_iteration (            {write one iteration to the CSV file}
  in      iter: sys_int_machine_t;     {iteration number, 0 = initial conditions}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  sec: double;                         {iteration time in seconds}

begin
  if tstep = 0.0
    then begin                         {X axis is iteration number}
      csv_out_int (csv, iter, stat);
      if sys_error(stat) then return;
      end
    else begin                         {X axis is time in seconds}
      sec := tstep * iter;             {make time of this iteration}
      csv_out_fp_free (csv, sec, 5, stat);
      if sys_error(stat) then return;
      end
    ;

  csv_out_fp_fixed (csv, last_p^.step, 6, stat);
  if sys_error(stat) then return;

  csv_out_fp_fixed (csv, last_p^.impl, 6, stat);
  if sys_error(stat) then return;

  csv_out_fp_fixed (csv, last_p^.rand, 6, stat);
  if sys_error(stat) then return;

  csv_out_line (csv, stat);
  end;
{
********************************************************************************
*
*   Subroutine WRITE_CSV_FILE (NAME, STAT)
*
*   Run the filters and write the result to the CSV file.
}
procedure write_csv_file (             {write the CSV file}
  in      name: string_treename_t;     {CSV file name to write to}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  iter: sys_int_machine_t;             {iteration number, 0 is initial conditions}
  pole_p: pole_p_t;                    {points to current filter pole}
  prev_p: pole_p_t;                    {points to previous filter pole}
  step_in: double;                     {input value for step filter}
  impl_in: double;                     {input value for impulse filter}
  rand_in: double;                     {input value for random noise filter}
  th_p: stepth_p_t;                    {points to next step threshold looking for}
  prev: double;                        {step response at previous iteration}
  r: double;                           {scratch floating point}

begin
  csv_out_open (name, csv, stat);      {open CSV file, init writing state}
  if sys_error(stat) then return;
  writeln ('Writing ', csv.conn.tnam.str:csv.conn.tnam.len);
{
*   Write CSV file header.
}
  if tstep = 0.0
    then begin                         {X axis is iterations}
      csv_out_str (csv, 'Iteration', stat);
      if sys_error(stat) then return;
      end
    else begin                         {X axis is time}
      csv_out_str (csv, 'Seconds', stat);
      if sys_error(stat) then return;
      end
    ;
  csv_out_str (csv, 'Step', stat);
  if sys_error(stat) then return;
  csv_out_str (csv, 'Impulse', stat);
  if sys_error(stat) then return;
  csv_out_str (csv, 'Noise', stat);
  if sys_error(stat) then return;
  csv_out_line (csv, stat);
  if sys_error(stat) then return;

  iter := 0;                           {init iteration to initial conditions}
  write_iteration (iter, stat);        {write initial conditions}
  if sys_error(stat) then return;

  th_p := stepth_list_p;               {init next step threshold looking for}
  prev := 0.0;                         {init value of previous iteration}
  while true do begin                  {back here each new iteration}
    iter := iter + 1;                  {make number of this iteration}

    pole_p := filt_p;                  {init filter pole to update}
    prev_p := nil;                     {init to no previous pole to use as input}
    while pole_p <> nil do begin       {loop thru the filter poles}
      if prev_p = nil
        then begin                     {no previous pole, use top level inputs}
          step_in := 1.0;
          if iter = 1
            then impl_in := 1.0
            else impl_in := 0.0;
          rand_in := math_rand_real (rand);
          end
        else begin                     {inputs to this pole from previous pole}
          step_in := prev_p^.step;
          impl_in := prev_p^.impl;
          rand_in := prev_p^.rand;
          end
        ;
      pole_p^.step := pole_p^.step + pole_p^.ff * (step_in - pole_p^.step); {update pole}
      pole_p^.impl := pole_p^.impl + pole_p^.ff * (impl_in - pole_p^.impl);
      pole_p^.rand := pole_p^.rand + pole_p^.ff * (rand_in - pole_p^.rand);
      prev_p := pole_p;                {this pole now becomes the previous}
      pole_p := pole_p^.next_p;        {advance to the next pole in this filter}
      end;                             {back to do next pole in the filter}

    write_iteration (iter, stat);      {write result of this iteration to CSV file}
    if sys_error(stat) then return;

    while                              {keep looking for another threshold crossed}
        (th_p <> nil) and then         {looking for a threshold ?}
        (last_p^.step >= th_p^.th)     {this threshold has been crossed ?}
        do begin
      th_p^.iter := iter;              {save first iteration at or after threshold}
      r :=                             {fraction into range from last iteration}
        (th_p^.th - prev) / (last_p^.step - prev);
      th_p^.iterf := r + iter - 1.0;   {make interpolated iteration of threshold cross}
      th_p^.found := true;             {indicate this threshold was found}
      th_p := th_p^.next_p;            {done with this threshold, on to next}
      end;                             {back to check this new threshold}

    if endstep <> 0 then begin         {check for end due to step response convergence}
      if last_p^.step >= endstep then exit;
      end;
    if enditer <> 0 then begin         {check for end due to iteration limit}
      if iter >= enditer then exit;
      end;
    prev := last_p^.step;              {curr result becomes previous for next iteration}
    end;                               {back to do next iteration}

  csv_out_close (csv, stat);
  end;
{
********************************************************************************
*
*   Subroutine PLOT_CSV_FILE (FNAM, STAT)
*
*   Show the plot resulting from the data in the CSV file FNAM.
}
procedure plot_csv_file (              {plot contents of CSV file}
  in      fnam: string_treename_t;     {name of CSV file to plot contents of}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  cmd: string_var8192_t;               {command line to execute}
  iounit: sys_sys_iounit_t;            {STDIO handles, unused}
  procid: sys_sys_proc_id_t;           {ID of the new process}

begin
  cmd.max := size_char(cmd.str);       {init local var string}

  string_vstring (cmd, 'csvplot '(0), -1); {build the command line}
  string_append_token (cmd, csv.conn.tnam);
  string_appends (cmd, ' -dev screen -miny 0 -maxy 1'(0));

  iounit := 0;
  sys_run (                            {run the command}
    cmd,                               {command line to run}
    sys_procio_none_k,                 {no I/O connection to this process}
    iounit, iounit, iounit,            {I/O unit IDs, not used}
    procid,                            {returned ID of the new process}
    stat);
  if sys_error(stat) then return;
  sys_proc_release (                   {let process run on its own}
    procid,                            {ID of the process to release}
    stat);
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize before reading the command line.
}
  filt_p := nil;                       {init to no filter poles defined}
  last_p := nil;
  npoles := 0;
  stepth_list_p := nil;                {init to no step response thresholds}
  enditer := 0;                        {no specific number of iterations limit}
  endstep := thresh_def;               {init step response that ends run}
  tstep := 0.0;                        {no specific iteration period known}
  math_rand_init_clock (rand);         {init random number generator seed}
  string_vstring (name, '/temp/plotfilt'(0), -1); {init output file name}
  util_mem_context_get (util_top_mem_context, mem_p); {create our to mem context}
  plot := true;                        {init to plot result}

  string_cmline_init;                  {init for reading the command line}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  {
  *   Handle the case of this command line option providing the shift bits for
  *   the next filter pole.  This is detected by the command line option being
  *   a valid numeric value.
  }
  string_t_fp2 (opt, r, stat);         {try to convert to numeric value in R}
  if not sys_error(stat) then begin    {this option is a numeric value ?}
    r := max(0.0, r);                  {clip shift bits to valid range}
    util_mem_grab (                    {alloc memory for this filter pole}
      sizeof(pole_p^),                 {amount of memory to allocate}
      mem_p^,                          {memory context to allocate under}
      false,                           {not for individual deallocation}
      pole_p);                         {returned pointer to the new memory}

    pole_p^.ff := 1.0 / (2**r);        {set the filter fraction}
    pole_p^.step := 0.0;               {init the filter values}
    pole_p^.impl := 0.0;
    pole_p^.rand := 0.5;
    pole_p^.next_p := nil;             {indicate at end of chain}

    if filt_p = nil
      then begin                       {this is first pole}
        filt_p := pole_p;              {init start of poles chaing}
        end
      else begin                       {adding to end of existing chain}
        last_p^.next_p := pole_p;      {link to new pole from last chain entry}
        end
      ;
    last_p := pole_p;                  {update pointer to last chain entry}
    npoles := npoles + 1;              {count one more pole in the filters}
    goto next_opt;                     {back for next command line option}
    end;                               {end of numeric command line option case}

  sys_error_none (stat);               {init to no error this command line option}
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-P -F -CSV -NP -N -TO -SEED -ST',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -P sec
}
1: begin
  string_cmline_token_fp2 (r, stat);
  if sys_error(stat) then goto parm_bad;
  tstep := max(0.0, r);
  end;
{
*   -F hz
}
2: begin
  string_cmline_token_fp2 (r, stat);
  if sys_error(stat) then goto parm_bad;
  tstep := 1.0 / max(1.0e-12, r);
  end;
{
*   -CSV name
}
3: begin
  string_cmline_token (name, stat);
  end;
{
*   -NP
}
4: begin
  plot := false;                       {inhibit plotting of result}
  end;
{
*   -N n
}
5: begin
  string_cmline_token_int (enditer, stat);
  enditer := max(0, enditer);
  endstep := 0.0;                      {disable end due to step convergence}
  end;
{
*   -TO end
}
6: begin
  string_cmline_token_fp2 (endstep, stat);
  enditer := 0;                        {disable end due to iteration limit}
  end;
{
*   -SEED seed
}
7: begin
  string_cmline_token_int (ii, stat);
  if sys_error(stat) then goto parm_bad;
  math_rand_init_int (ii, rand);
  end;
{
*   -ST response
}
8: begin
  string_cmline_token_fp2 (r, stat);   {get the step response threshold into R}
  if sys_error(stat) then goto parm_bad;
  stepth_add (r);                      {add this threshold to the list}
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   Done reading and processing the command line options.
}
  if filt_p = nil then begin
    writeln ('No filter poles defined.');
    sys_bomb;
    end;

  write_csv_file (name, stat);         {run filters, write to the CSV file}
  sys_error_abort (stat, '', '', nil, 0);

  show_thresh;                         {show any step response thresholds found}

  if plot then begin                   {show results graphically}
    plot_csv_file (csv.conn.tnam, stat);
    sys_error_abort (stat, '', '', nil, 0);
    end;
  end.

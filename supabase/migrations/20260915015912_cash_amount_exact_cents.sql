-- Valor à vista = 8% exatos sobre o valor da série, sem arredondar para o real (decisão da escola).
update public.grade_offerings
   set cash_amount_cents = round(amount_cents * 0.92)
 where academic_year = 2027;

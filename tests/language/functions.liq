#!../../src/liquidsoap ../../libs/stdlib.liq ../../libs/deprecations.liq

%include "test.liq"

def t(x, y)
  if x != y then
    print("Failure: got #{x} instead of #{y}")
    test.fail()
  end
end

def f() =
  def f(~(foo:int), ~(bar:string)="123", (x:source), (y:int)=123) =
    ()
  end

  # Arguments with same name
  def f(x, x)
    x
  end
  t(f(2, 3), 3)

  # Free variables with same name
  x = 4
  x = 5
  def f()
    x
  end
  t(f(), 5)

  test.pass()
end

test.check(f)

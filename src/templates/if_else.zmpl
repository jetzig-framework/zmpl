@if ($.foo.bar == 999 and $.foo.baz >= 5 and $.foo.qux.quux < 3)
    unexpected here
@else if ($.foo.bar == 1 and $.foo.baz == 3 and $.foo.qux.quux == 4)
    expected here
    @if ($.foo.bar == 1)
        nested expected here
        foo.bar is {{$.foo.bar}}
        @if ($.foo.qux.quux != 999)
            double nested expected here
            foo.qux.quux is {{$.foo.qux.quux}}
        @end
    @end
@else
    unexpected here
@end

@if ($.foo.missing) |missing|
  unexpected: {{missing}}
@else
  expected: `missing` is not here
@end

@if ($.foo.corge == "I am corge")
  corge says "{{$.foo.corge}}"
@end

@if ($.foo.corge != "I am not corge")
  corge confirms "{{$.foo.corge}}"
@end

@if (false)
  @if (true)
    unexpected
  @end
@else if (false)
  unexpected
@else
  expected: else
@end

@if ($.foo.bar) |bar|
  bar is {{bar}}
@end

@if ($.foo.truthy)
  expected truth
@end

@if ($.foo.truthy and !$.foo.falsey)
  another expected truth
@end

@if ($.foo.falsey)
  unexpected falsehood
@end

@if ($.foo.nonexistent) |_|
  unexpected nonexistent
@end

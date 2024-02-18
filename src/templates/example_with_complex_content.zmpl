<html>
  if (1 == 0) {
    <div>Hello</div>
  } else {
    <div>Hi</div>
  }

  <div style="background-color: #ff0000">
    const values = .{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" };
    <ol>
      inline for (0..9) |index| {
        const count = index + 1;
        const human_count = values[index];
        <li>This is item number {:count}, {:human_count}</li>
      }
    </ol>
  </div>

  <ol>
    if (zmpl.value) |*value| {
      var it = value.array.iterator();

      while (it.next()) |item| {
        <div>{item}</div>
      }
    }
  </ol>

  <span>{.some.missing.value}</span>
  <span>{.0}</span>
  <span>{.1}</span>
  <span>{.2}</span>
  <span>{.3}</span>
  <span>{.4}</span>
</html>

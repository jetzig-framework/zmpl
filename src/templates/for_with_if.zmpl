<div>
    @if ($.foo)
        @partial thing("foo", "bar")
    @end
    <hr/>
    <table class="table-auto">
        <tbody>
        @for ($.things) |thing| {
            <tr>
                <td>
                    @partial thing(thing.foo, thing.bar)
                </td>
                <td>
                    @if ($.foo)
                        @partial thing(thing.bar, thing.foo)
                    @end
                </td>
            </tr>
        }
        </tbody>
    </table>
</div>

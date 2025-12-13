// Memory benchmark - 600k objects
// Tests: GC and memory allocation

var COUNT = 600000;
var log = typeof print === 'function' ? print : console.log;

var objects = [];
for (var i = 0; i < COUNT; i++) {
    objects.push({ id: i, value: 'test' + i });
}

log('Created ' + objects.length + ' objects');

// Web worker

console.log( "worker", Math.random(100) );

var number = Math.floor(Math.random() * 1000000);

onmessage = function(e) {
  if (e.data === "close") {
    close();
  }
  if (e.data.indexOf("#") === 0) {
    number = e.data
  }
  postMessage({
    number: number,
    result: e.data
  });
}

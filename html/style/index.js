$(document).ready(function() {

  function pulsate() {
    $(".pulsate").
      animate({opacity: 0.2}, 1000, "linear").
      animate({opacity: 1}, 1000, "linear", pulsate);
  }
  pulsate();

});

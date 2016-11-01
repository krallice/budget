$(document).ready(function() {

  function pulsate() {
    $(".pulsate").
      animate({opacity: 0.2}, 1000, "linear").
      animate({opacity: 1}, 1000, "linear", pulsate);
  }
  pulsate();

  $('#rainbowtitle').rainbow({animate:true,animateInterval:100,colors:['#FF0000','#f26522','#fff200','#00a651','#28abe2','#2e3192','#6868ff']});

});

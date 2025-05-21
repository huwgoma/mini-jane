$( document ).ready(function(){
  
  $("form.delete").submit(function(event) {
    event.preventDefault();
    event.stopPropagation();

    if (confirm("Are you sure? This cannot be undone!")) {
      this.submit();
    }
  })
})
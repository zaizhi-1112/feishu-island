document.querySelectorAll('[data-reading-size]').forEach(button=>button.addEventListener('click',()=>{document.body.style.fontSize=button.dataset.readingSize;}));
